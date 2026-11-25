package com.nookflow.license.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "nookflow.payment")
public record PaymentProperties(
        boolean enabled,
        String baseUrl,
        String merchantId,
        String merchantPrivateKey,
        String platformPublicKey,
        String deliveryEncryptionKey,
        String publicBaseUrl,
        int productPriceCents,
        int orderExpiryMinutes,
        int timestampSkewSeconds,
        int providerQueryCooldownSeconds
) {
}
