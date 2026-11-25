package com.nookflow.license.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nookflow.license.config.LicenseProperties;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.interfaces.ECPrivateKey;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.Base64;
import java.util.Map;
import org.junit.jupiter.api.Test;

final class LicenseCryptoTest {
    private static final Base64.Encoder URL_ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Instant NOW = Instant.parse("2026-08-07T08:00:00Z");

    @Test
    void signsRawP256TokensAndReadsThemBack() throws Exception {
        KeyPair serverKey = keyPair();
        LicenseCrypto crypto = crypto(serverKey);

        String token = crypto.signLicense("license-1", "device-1");
        String[] components = token.split("\\.");

        assertThat(Base64.getUrlDecoder().decode(components[1])).hasSize(64);
        assertThat(crypto.verifyAndReadLicense(token))
                .isEqualTo(new LicenseCrypto.SignedPayload("license-1", "device-1"));
    }

    @Test
    void verifiesTheRawSignatureProducedByTheMacProtocol() throws Exception {
        KeyPair serverKey = keyPair();
        KeyPair deviceKey = keyPair();
        LicenseCrypto crypto = crypto(serverKey);
        long timestamp = NOW.toEpochMilli();
        String subject = "NFABCDEABCDEABCDE";
        String message = "activate\n" + timestamp + "\n" + subject;

        Signature signer = Signature.getInstance("SHA256withECDSA");
        signer.initSign(deviceKey.getPrivate());
        signer.update(message.getBytes(StandardCharsets.UTF_8));

        var publicKey = (ECPublicKey) deviceKey.getPublic();
        byte[] x963 = new byte[65];
        x963[0] = 0x04;
        write32(publicKey.getW().getAffineX(), x963, 1);
        write32(publicKey.getW().getAffineY(), x963, 33);

        var verified = crypto.verifyDeviceProof(
                encode(x963), timestamp, encode(derToRaw(signer.sign())), "activate", subject
        );
        assertThat(verified.hash()).hasSize(64);
        assertThat(verified.publicKey()).isEqualTo(encode(x963));
    }

    private static LicenseCrypto crypto(KeyPair keyPair) throws Exception {
        var privateKey = (ECPrivateKey) keyPair.getPrivate();
        var publicKey = (ECPublicKey) keyPair.getPublic();
        String jwk = new ObjectMapper().writeValueAsString(Map.of(
                "kty", "EC",
                "crv", "P-256",
                "x", encode32(publicKey.getW().getAffineX()),
                "y", encode32(publicKey.getW().getAffineY()),
                "d", encode32(privateKey.getS())
        ));
        var properties = new LicenseProperties("pepper", jwk, "admin", 14, 30, 300, 60);
        return new LicenseCrypto(new ObjectMapper(), properties, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    private static KeyPair keyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return generator.generateKeyPair();
    }

    private static String encode32(BigInteger value) {
        byte[] result = new byte[32];
        write32(value, result, 0);
        return encode(result);
    }

    private static void write32(BigInteger value, byte[] target, int offset) {
        byte[] source = value.toByteArray();
        int sourceOffset = source.length > 32 ? source.length - 32 : 0;
        int length = Math.min(32, source.length);
        System.arraycopy(source, sourceOffset, target, offset + 32 - length, length);
    }

    private static String encode(byte[] value) {
        return URL_ENCODER.encodeToString(value);
    }

    private static byte[] derToRaw(byte[] der) {
        int index = 3;
        int rLength = der[index++] & 0xff;
        byte[] r = Arrays.copyOfRange(der, index, index + rLength);
        index += rLength + 1;
        int sLength = der[index++] & 0xff;
        byte[] s = Arrays.copyOfRange(der, index, index + sLength);
        byte[] raw = new byte[64];
        copyInteger(r, raw, 0);
        copyInteger(s, raw, 32);
        return raw;
    }

    private static void copyInteger(byte[] value, byte[] target, int offset) {
        int sourceOffset = value.length > 32 && value[0] == 0 ? 1 : 0;
        int length = value.length - sourceOffset;
        System.arraycopy(value, sourceOffset, target, offset + 32 - length, length);
    }
}
