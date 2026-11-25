package com.nookflow.license.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "nookflow.mail")
public record MailDeliveryProperties(
        boolean enabled,
        String fromAddress,
        String fromName,
        int maxAttempts,
        int retryDelaySeconds,
        int pollDelayMillis
) {
    public int effectiveMaxAttempts() {
        return Math.max(1, maxAttempts);
    }

    public int effectiveRetryDelaySeconds() {
        return Math.max(10, retryDelaySeconds);
    }
}
