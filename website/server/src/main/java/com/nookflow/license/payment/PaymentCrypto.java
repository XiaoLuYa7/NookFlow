package com.nookflow.license.payment;

import com.nookflow.license.api.ApiException;
import com.nookflow.license.config.PaymentProperties;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.SecureRandom;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public final class PaymentCrypto {
    private static final Base64.Encoder BASE64 = Base64.getEncoder();
    private static final Base64.Encoder BASE64_URL = Base64.getUrlEncoder().withoutPadding();

    private final PaymentProperties properties;
    private final SecureRandom random = new SecureRandom();
    private final PrivateKey merchantPrivateKey;
    private final PublicKey platformPublicKey;
    private final SecretKey deliveryKey;

    public PaymentCrypto(PaymentProperties properties) {
        this.properties = properties;
        if (!properties.enabled()) {
            merchantPrivateKey = null;
            platformPublicKey = null;
            deliveryKey = null;
            return;
        }
        try {
            requireConfiguration(properties);
            KeyFactory factory = KeyFactory.getInstance("RSA");
            merchantPrivateKey = factory.generatePrivate(new PKCS8EncodedKeySpec(decodePem(properties.merchantPrivateKey())));
            platformPublicKey = factory.generatePublic(new X509EncodedKeySpec(decodePem(properties.platformPublicKey())));
            byte[] keyBytes = decodeBase64(properties.deliveryEncryptionKey());
            if (keyBytes.length != 32) {
                throw new IllegalArgumentException("PAYMENT_DELIVERY_ENCRYPTION_KEY must decode to 32 bytes");
            }
            deliveryKey = new SecretKeySpec(keyBytes, "AES");
        } catch (Exception error) {
            throw new IllegalStateException("Invalid payment cryptography configuration", error);
        }
    }

    public String sign(Map<String, String> parameters) {
        ensureEnabled();
        try {
            Signature signer = Signature.getInstance("SHA256withRSA");
            signer.initSign(merchantPrivateKey);
            signer.update(canonical(parameters).getBytes(StandardCharsets.UTF_8));
            return BASE64.encodeToString(signer.sign());
        } catch (Exception error) {
            throw new IllegalStateException("Unable to sign payment request", error);
        }
    }

    public boolean verify(Map<String, String> parameters) {
        ensureEnabled();
        String encodedSignature = parameters.get("sign");
        if (encodedSignature == null || encodedSignature.isBlank()) return false;
        try {
            Signature verifier = Signature.getInstance("SHA256withRSA");
            verifier.initVerify(platformPublicKey);
            verifier.update(canonical(parameters).getBytes(StandardCharsets.UTF_8));
            return verifier.verify(Base64.getDecoder().decode(encodedSignature));
        } catch (Exception ignored) {
            return false;
        }
    }

    public String encryptActivationCode(String orderNo, String code) {
        ensureEnabled();
        try {
            byte[] nonce = new byte[12];
            random.nextBytes(nonce);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, deliveryKey, new GCMParameterSpec(128, nonce));
            cipher.updateAAD(orderNo.getBytes(StandardCharsets.UTF_8));
            byte[] ciphertext = cipher.doFinal(code.getBytes(StandardCharsets.UTF_8));
            return "v1." + BASE64_URL.encodeToString(nonce) + "." + BASE64_URL.encodeToString(ciphertext);
        } catch (Exception error) {
            throw new IllegalStateException("Unable to protect activation code", error);
        }
    }

    public String decryptActivationCode(String orderNo, String encryptedCode) {
        ensureEnabled();
        try {
            String[] components = encryptedCode.split("\\.");
            if (components.length != 3 || !components[0].equals("v1")) {
                throw new IllegalArgumentException("Unsupported delivery payload");
            }
            byte[] nonce = Base64.getUrlDecoder().decode(components[1]);
            byte[] ciphertext = Base64.getUrlDecoder().decode(components[2]);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, deliveryKey, new GCMParameterSpec(128, nonce));
            cipher.updateAAD(orderNo.getBytes(StandardCharsets.UTF_8));
            return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
        } catch (Exception error) {
            throw new IllegalStateException("Unable to read activation code", error);
        }
    }

    public static String canonical(Map<String, String> parameters) {
        return new TreeMap<>(parameters).entrySet().stream()
                .filter(entry -> !entry.getKey().equals("sign") && !entry.getKey().equals("sign_type"))
                .filter(entry -> entry.getValue() != null && !entry.getValue().isBlank())
                .map(entry -> entry.getKey() + "=" + entry.getValue())
                .collect(Collectors.joining("&"));
    }

    public static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
    }

    private void ensureEnabled() {
        if (!properties.enabled()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "payment_unavailable");
        }
    }

    private static void requireConfiguration(PaymentProperties properties) {
        if (properties.merchantId() == null || properties.merchantId().isBlank()
                || properties.merchantPrivateKey() == null || properties.merchantPrivateKey().isBlank()
                || properties.platformPublicKey() == null || properties.platformPublicKey().isBlank()
                || properties.deliveryEncryptionKey() == null || properties.deliveryEncryptionKey().isBlank()
                || properties.publicBaseUrl() == null || properties.publicBaseUrl().isBlank()) {
            throw new IllegalArgumentException("Payment is enabled but required settings are missing");
        }
        if (properties.productPriceCents() < 1) {
            throw new IllegalArgumentException("NOOKFLOW_PRO_PRICE_CENTS must be positive");
        }
    }

    private static byte[] decodePem(String value) {
        String normalized = value.replace("\\n", "\n")
                .replaceAll("-----BEGIN [^-]+-----", "")
                .replaceAll("-----END [^-]+-----", "")
                .replaceAll("\\s", "");
        return Base64.getDecoder().decode(normalized);
    }

    private static byte[] decodeBase64(String value) {
        try {
            return Base64.getDecoder().decode(value);
        } catch (IllegalArgumentException ignored) {
            return Base64.getUrlDecoder().decode(value);
        }
    }
}
