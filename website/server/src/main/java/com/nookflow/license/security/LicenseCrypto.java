package com.nookflow.license.security;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nookflow.license.api.ApiException;
import com.nookflow.license.config.LicenseProperties;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPrivateKeySpec;
import java.security.spec.ECPublicKeySpec;
import java.time.Clock;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public final class LicenseCrypto {
    private static final Base64.Decoder URL_DECODER = Base64.getUrlDecoder();
    private static final Base64.Encoder URL_ENCODER = Base64.getUrlEncoder().withoutPadding();

    private final ObjectMapper mapper;
    private final LicenseProperties properties;
    private final Clock clock;
    private final ECParameterSpec curve;
    private final PrivateKey signingKey;

    @Autowired
    public LicenseCrypto(ObjectMapper mapper, LicenseProperties properties) throws Exception {
        this(mapper, properties, Clock.systemUTC());
    }

    LicenseCrypto(ObjectMapper mapper, LicenseProperties properties, Clock clock) throws Exception {
        this.mapper = mapper;
        this.properties = properties;
        this.clock = clock;
        AlgorithmParameters parameters = AlgorithmParameters.getInstance("EC");
        parameters.init(new ECGenParameterSpec("secp256r1"));
        curve = parameters.getParameterSpec(ECParameterSpec.class);
        signingKey = readPrivateKey(properties.signingPrivateJwk());
    }

    public VerifiedDevice verifyDeviceProof(
            String publicKeyValue,
            long timestamp,
            String proofValue,
            String action,
            String subject
    ) {
        long now = clock.millis();
        if (Math.abs(now - timestamp) > properties.requestClockSkewSeconds() * 1000L) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "stale_request");
        }
        try {
            byte[] publicKeyBytes = decodeUrl(publicKeyValue);
            if (publicKeyBytes.length != 65 || publicKeyBytes[0] != 0x04) {
                throw new IllegalArgumentException("Invalid P-256 public key");
            }
            var point = new ECPoint(
                    new BigInteger(1, Arrays.copyOfRange(publicKeyBytes, 1, 33)),
                    new BigInteger(1, Arrays.copyOfRange(publicKeyBytes, 33, 65))
            );
            var publicKey = KeyFactory.getInstance("EC")
                    .generatePublic(new ECPublicKeySpec(point, curve));
            Signature verifier = Signature.getInstance("SHA256withECDSA");
            verifier.initVerify(publicKey);
            verifier.update((action + "\n" + timestamp + "\n" + subject).getBytes(StandardCharsets.UTF_8));
            if (!verifier.verify(rawToDer(decodeUrl(proofValue)))) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_proof");
            }
            return new VerifiedDevice(hex(sha256(publicKeyBytes)), publicKeyValue);
        } catch (ApiException error) {
            throw error;
        } catch (Exception error) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_proof");
        }
    }

    public String signLicense(String licenseId, String deviceHash) {
        try {
            long now = clock.millis();
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("licenseID", licenseId);
            payload.put("product", "nookflow_pro");
            payload.put("deviceID", deviceHash);
            payload.put("issuedAt", now);
            payload.put("checkAfter", now + properties.checkAfterDays() * 86_400_000L);
            payload.put("offlineUntil", now + properties.offlineGraceDays() * 86_400_000L);
            byte[] payloadBytes = mapper.writeValueAsBytes(payload);
            Signature signer = Signature.getInstance("SHA256withECDSA");
            signer.initSign(signingKey);
            signer.update(payloadBytes);
            return encodeUrl(payloadBytes) + "." + encodeUrl(derToRaw(signer.sign()));
        } catch (Exception error) {
            throw new IllegalStateException("Unable to sign license", error);
        }
    }

    public SignedPayload verifyAndReadLicense(String token) {
        try {
            String[] components = token.split("\\.", -1);
            if (components.length != 2) throw new IllegalArgumentException("Invalid token");
            byte[] payload = decodeUrl(components[0]);
            byte[] signature = decodeUrl(components[1]);

            Map<String, String> jwk = mapper.readValue(
                    properties.signingPrivateJwk(), new TypeReference<>() { });
            ECPoint point = new ECPoint(
                    new BigInteger(1, decodeUrl(jwk.get("x"))),
                    new BigInteger(1, decodeUrl(jwk.get("y")))
            );
            var publicKey = KeyFactory.getInstance("EC")
                    .generatePublic(new ECPublicKeySpec(point, curve));
            Signature verifier = Signature.getInstance("SHA256withECDSA");
            verifier.initVerify(publicKey);
            verifier.update(payload);
            if (!verifier.verify(rawToDer(signature))) {
                throw new IllegalArgumentException("Invalid token signature");
            }
            Map<String, Object> values = mapper.readValue(payload, new TypeReference<>() { });
            return new SignedPayload(
                    String.valueOf(values.get("licenseID")),
                    String.valueOf(values.get("deviceID"))
            );
        } catch (Exception error) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_license");
        }
    }

    public String hashCode(String normalizedCode) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(properties.codePepper().getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return hex(mac.doFinal(normalizedCode.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            throw new IllegalStateException("Unable to hash activation code", error);
        }
    }

    private PrivateKey readPrivateKey(String encodedJwk) throws Exception {
        Map<String, String> jwk = mapper.readValue(encodedJwk, new TypeReference<>() { });
        return KeyFactory.getInstance("EC").generatePrivate(
                new ECPrivateKeySpec(new BigInteger(1, decodeUrl(jwk.get("d"))), curve)
        );
    }

    private static byte[] sha256(byte[] value) throws Exception {
        return MessageDigest.getInstance("SHA-256").digest(value);
    }

    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) result.append(String.format("%02x", value));
        return result.toString();
    }

    private static byte[] decodeUrl(String value) {
        return URL_DECODER.decode(value);
    }

    private static String encodeUrl(byte[] value) {
        return URL_ENCODER.encodeToString(value);
    }

    private static byte[] rawToDer(byte[] raw) {
        if (raw.length != 64) throw new IllegalArgumentException("Invalid raw ECDSA signature");
        byte[] r = unsignedInteger(Arrays.copyOfRange(raw, 0, 32));
        byte[] s = unsignedInteger(Arrays.copyOfRange(raw, 32, 64));
        int bodyLength = 4 + r.length + s.length;
        byte[] der = new byte[2 + bodyLength];
        int index = 0;
        der[index++] = 0x30;
        der[index++] = (byte) bodyLength;
        der[index++] = 0x02;
        der[index++] = (byte) r.length;
        System.arraycopy(r, 0, der, index, r.length);
        index += r.length;
        der[index++] = 0x02;
        der[index++] = (byte) s.length;
        System.arraycopy(s, 0, der, index, s.length);
        return der;
    }

    private static byte[] derToRaw(byte[] der) {
        int index = 2;
        if (der.length < 8 || der[0] != 0x30 || der[index++] != 0x02) {
            throw new IllegalArgumentException("Invalid DER ECDSA signature");
        }
        int rLength = der[index++] & 0xff;
        byte[] r = Arrays.copyOfRange(der, index, index + rLength);
        index += rLength;
        if (der[index++] != 0x02) throw new IllegalArgumentException("Invalid DER ECDSA signature");
        int sLength = der[index++] & 0xff;
        byte[] s = Arrays.copyOfRange(der, index, index + sLength);
        byte[] raw = new byte[64];
        copyInteger(r, raw, 0);
        copyInteger(s, raw, 32);
        return raw;
    }

    private static byte[] unsignedInteger(byte[] value) {
        int first = 0;
        while (first < value.length - 1 && value[first] == 0) first++;
        byte[] result = Arrays.copyOfRange(value, first, value.length);
        if ((result[0] & 0x80) != 0) {
            byte[] padded = new byte[result.length + 1];
            System.arraycopy(result, 0, padded, 1, result.length);
            return padded;
        }
        return result;
    }

    private static void copyInteger(byte[] value, byte[] target, int offset) {
        int sourceOffset = value.length > 32 && value[0] == 0 ? 1 : 0;
        int length = value.length - sourceOffset;
        if (length > 32) throw new IllegalArgumentException("Invalid ECDSA integer");
        System.arraycopy(value, sourceOffset, target, offset + 32 - length, length);
    }

    public record VerifiedDevice(String hash, String publicKey) {
    }

    public record SignedPayload(String licenseId, String deviceHash) {
    }
}
