package com.nookflow.license.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "nookflow.license")
public record LicenseProperties(
        String codePepper,
        String signingPrivateJwk,
        String adminToken,
        int checkAfterDays,
        int offlineGraceDays,
        int requestClockSkewSeconds,
        int rateLimitPerMinute
) {
}
