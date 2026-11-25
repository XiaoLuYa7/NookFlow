package com.nookflow.license.payment;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.nookflow.license.config.PaymentProperties;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

final class PaymentCryptoTest {
    @Test
    void canonicalizesParametersWithoutSignatureFields() {
        Map<String, String> parameters = new LinkedHashMap<>();
        parameters.put("z", "last");
        parameters.put("sign", "ignored");
        parameters.put("blank", "");
        parameters.put("a", "first");
        parameters.put("sign_type", "RSA");

        assertThat(PaymentCrypto.canonical(parameters)).isEqualTo("a=first&z=last");
    }

    @Test
    void signsAndVerifiesProviderPayloads() throws Exception {
        PaymentCrypto crypto = crypto(keyPair());
        Map<String, String> parameters = new LinkedHashMap<>();
        parameters.put("pid", "10001");
        parameters.put("money", "0.01");
        parameters.put("timestamp", "1786435200");
        parameters.put("sign_type", "RSA");
        parameters.put("sign", crypto.sign(parameters));

        assertThat(crypto.verify(parameters)).isTrue();
        parameters.put("money", "1.00");
        assertThat(crypto.verify(parameters)).isFalse();
    }

    @Test
    void protectsActivationCodeWithOrderBoundAuthenticatedEncryption() throws Exception {
        PaymentCrypto crypto = crypto(keyPair());
        String encrypted = crypto.encryptActivationCode("NF-ORDER-1", "NF-ABCDE-FGHIJ-KLMNO");

        assertThat(encrypted).doesNotContain("NF-ABCDE");
        assertThat(crypto.decryptActivationCode("NF-ORDER-1", encrypted))
                .isEqualTo("NF-ABCDE-FGHIJ-KLMNO");
        assertThatThrownBy(() -> crypto.decryptActivationCode("NF-ORDER-2", encrypted))
                .isInstanceOf(IllegalStateException.class);
    }

    private static PaymentCrypto crypto(KeyPair keyPair) {
        String privateKey = Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded());
        String publicKey = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());
        String deliveryKey = Base64.getEncoder().encodeToString(new byte[32]);
        var properties = new PaymentProperties(
                true,
                "https://pay.example.test",
                "10001",
                privateKey,
                publicKey,
                deliveryKey,
                "https://nookflow.example.test",
                1,
                30,
                600,
                8
        );
        return new PaymentCrypto(properties);
    }

    private static KeyPair keyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        return generator.generateKeyPair();
    }
}
