package com.nookflow.license.service;

import com.nookflow.license.api.ApiException;
import com.nookflow.license.security.LicenseCrypto;
import java.security.SecureRandom;
import java.util.Locale;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LicenseService {
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    private final JdbcTemplate jdbc;
    private final LicenseCrypto crypto;
    private final SecureRandom random = new SecureRandom();

    public LicenseService(JdbcTemplate jdbc, LicenseCrypto crypto) {
        this.jdbc = jdbc;
        this.crypto = crypto;
    }

    @Transactional
    public String activate(String code, String publicKey, long timestamp, String proof) {
        String normalizedCode = normalizeCode(code);
        if (normalizedCode.length() != 17) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_code");
        }
        var device = crypto.verifyDeviceProof(publicKey, timestamp, proof, "activate", normalizedCode);
        LicenseRow license = findLicenseForUpdate(crypto.hashCode(normalizedCode));
        assertLicenseUsable(license);

        DeviceRow binding = findDevice(license.id());
        long now = System.currentTimeMillis();
        if (binding == null) {
            insertDevice(license.id(), device.hash(), device.publicKey(), now);
        } else if (binding.status().equals("ACTIVE") && !binding.deviceHash().equals(device.hash())) {
            recordEvent(license.id(), device.hash(), "REJECT", now);
            throw new ApiException(HttpStatus.CONFLICT, "already_activated");
        } else if (binding.status().equals("DEACTIVATED")) {
            if (license.transferCount() >= license.transferLimit()) {
                throw new ApiException(HttpStatus.CONFLICT, "transfer_limit_reached");
            }
            jdbc.update("""
                    UPDATE license_devices
                    SET device_hash = ?, device_public_key = ?, status = 'ACTIVE',
                        activated_at = ?, deactivated_at = NULL, last_seen_at = ?, updated_at = ?
                    WHERE license_id = ?
                    """, device.hash(), device.publicKey(), now, now, now, license.id());
        } else {
            jdbc.update("""
                    UPDATE license_devices
                    SET device_public_key = ?, last_seen_at = ?, updated_at = ?
                    WHERE license_id = ?
                    """, device.publicKey(), now, now, license.id());
        }

        jdbc.update("UPDATE licenses SET last_verified_at = ?, updated_at = ? WHERE id = ?", now, now, license.id());
        recordEvent(license.id(), device.hash(), "ACTIVATE", now);
        return crypto.signLicense(license.id(), device.hash());
    }

    @Transactional
    public String validate(String token, String publicKey, long timestamp, String proof) {
        var device = crypto.verifyDeviceProof(publicKey, timestamp, proof, "validate", token);
        var payload = crypto.verifyAndReadLicense(token);
        if (!payload.deviceHash().equals(device.hash())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_license");
        }

        LicenseRow license = findLicenseByIdForUpdate(payload.licenseId());
        assertLicenseUsable(license);
        DeviceRow binding = findDevice(license.id());
        if (binding == null || !binding.status().equals("ACTIVE") || !binding.deviceHash().equals(device.hash())) {
            throw new ApiException(HttpStatus.FORBIDDEN, "license_revoked");
        }

        long now = System.currentTimeMillis();
        jdbc.update("UPDATE license_devices SET last_seen_at = ?, updated_at = ? WHERE license_id = ?", now, now, license.id());
        jdbc.update("UPDATE licenses SET last_verified_at = ?, updated_at = ? WHERE id = ?", now, now, license.id());
        recordEvent(license.id(), device.hash(), "VALIDATE", now);
        return crypto.signLicense(license.id(), device.hash());
    }

    @Transactional
    public void deactivate(String token, String publicKey, long timestamp, String proof) {
        var device = crypto.verifyDeviceProof(publicKey, timestamp, proof, "deactivate", token);
        var payload = crypto.verifyAndReadLicense(token);
        if (!payload.deviceHash().equals(device.hash())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_license");
        }

        LicenseRow license = findLicenseByIdForUpdate(payload.licenseId());
        DeviceRow binding = findDevice(license.id());
        if (binding != null && binding.status().equals("ACTIVE") && binding.deviceHash().equals(device.hash())) {
            long now = System.currentTimeMillis();
            jdbc.update("""
                    UPDATE license_devices
                    SET status = 'DEACTIVATED', deactivated_at = ?, updated_at = ?
                    WHERE license_id = ?
                    """, now, now, license.id());
            jdbc.update("""
                    UPDATE licenses
                    SET transfer_count = transfer_count + 1, updated_at = ?
                    WHERE id = ?
                    """, now, license.id());
            recordEvent(license.id(), device.hash(), "DEACTIVATE", now);
        }
    }

    @Transactional
    public CreatedLicense createLicense(String note) {
        long now = System.currentTimeMillis();
        Long productId = jdbc.queryForObject(
                "SELECT id FROM products WHERE code = 'NOOKFLOW_PRO' AND status = 'ACTIVE' LIMIT 1",
                Long.class
        );
        for (int attempt = 0; attempt < 5; attempt++) {
            String code = randomCode();
            String id = UUID.randomUUID().toString();
            try {
                jdbc.update("""
                        INSERT INTO licenses
                            (id, product_id, code_hash, tier, status, max_devices, transfer_limit,
                             transfer_count, note, issued_at, created_at, updated_at)
                        VALUES (?, ?, ?, 'pro', 'ACTIVE', 1, 3, 0, ?, ?, ?, ?)
                        """, id, productId, crypto.hashCode(normalizeCode(code)), cleanNote(note), now, now, now);
                return new CreatedLicense(id, code, "pro");
            } catch (DuplicateKeyException ignored) {
                // Extremely unlikely; generate a new high-entropy code.
            }
        }
        throw new IllegalStateException("Unable to allocate a unique activation code");
    }

    public boolean databaseHealthy() {
        try {
            return jdbc.queryForObject("SELECT 1", Integer.class) == 1;
        } catch (Exception ignored) {
            return false;
        }
    }

    private LicenseRow findLicenseForUpdate(String codeHash) {
        return jdbc.query("""
                SELECT id, status, transfer_limit, transfer_count, expire_at
                FROM licenses WHERE code_hash = ? LIMIT 1 FOR UPDATE
                """, (result, row) -> new LicenseRow(
                result.getString("id"), result.getString("status"),
                result.getInt("transfer_limit"), result.getInt("transfer_count"),
                result.getObject("expire_at", Long.class)
        ), codeHash).stream().findFirst().orElseThrow(
                () -> new ApiException(HttpStatus.NOT_FOUND, "invalid_code")
        );
    }

    private LicenseRow findLicenseByIdForUpdate(String id) {
        return jdbc.query("""
                SELECT id, status, transfer_limit, transfer_count, expire_at
                FROM licenses WHERE id = ? LIMIT 1 FOR UPDATE
                """, (result, row) -> new LicenseRow(
                result.getString("id"), result.getString("status"),
                result.getInt("transfer_limit"), result.getInt("transfer_count"),
                result.getObject("expire_at", Long.class)
        ), id).stream().findFirst().orElseThrow(
                () -> new ApiException(HttpStatus.FORBIDDEN, "license_revoked")
        );
    }

    private DeviceRow findDevice(String licenseId) {
        return jdbc.query("""
                SELECT device_hash, status FROM license_devices WHERE license_id = ? LIMIT 1
                """, (result, row) -> new DeviceRow(
                result.getString("device_hash"), result.getString("status")
        ), licenseId).stream().findFirst().orElse(null);
    }

    private void insertDevice(String licenseId, String deviceHash, String publicKey, long now) {
        jdbc.update("""
                INSERT INTO license_devices
                    (id, license_id, device_hash, device_public_key, status, activated_at,
                     last_seen_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'ACTIVE', ?, ?, ?, ?)
                """, UUID.randomUUID().toString(), licenseId, deviceHash, publicKey, now, now, now, now);
    }

    private void recordEvent(String licenseId, String deviceHash, String action, long now) {
        jdbc.update("""
                INSERT INTO activation_events (license_id, device_hash, action, created_at)
                VALUES (?, ?, ?, ?)
                """, licenseId, deviceHash, action, now);
    }

    private static void assertLicenseUsable(LicenseRow license) {
        if (!license.status().equals("ACTIVE")) {
            throw new ApiException(HttpStatus.FORBIDDEN, "license_revoked");
        }
        if (license.expireAt() != null && license.expireAt() <= System.currentTimeMillis()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "license_expired");
        }
    }

    private String randomCode() {
        StringBuilder value = new StringBuilder(15);
        for (int index = 0; index < 15; index++) {
            value.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        return "NF-" + value.substring(0, 5) + "-" + value.substring(5, 10) + "-" + value.substring(10);
    }

    private static String normalizeCode(String value) {
        return value == null ? "" : value.toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9]", "");
    }

    private static String cleanNote(String note) {
        if (note == null || note.isBlank()) return null;
        return note.trim().substring(0, Math.min(160, note.trim().length()));
    }

    private record LicenseRow(String id, String status, int transferLimit, int transferCount, Long expireAt) {
    }

    private record DeviceRow(String deviceHash, String status) {
    }

    public record CreatedLicense(String id, String code, String tier) {
    }
}
