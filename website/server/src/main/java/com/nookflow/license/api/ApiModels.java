package com.nookflow.license.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public final class ApiModels {
    private ApiModels() {
    }

    public record ActivationRequest(
            @NotBlank String code,
            @NotBlank String devicePublicKey,
            @NotNull Long timestamp,
            @NotBlank String proof
    ) {
    }

    public record SignedLicenseRequest(
            @NotBlank String signedLicense,
            @NotBlank String devicePublicKey,
            @NotNull Long timestamp,
            @NotBlank String proof
    ) {
    }

    public record LicenseResponse(String signedLicense) {
    }

    public record DeactivationResponse(boolean deactivated) {
    }

    public record CreateLicenseRequest(String note) {
    }

    public record CreatedLicenseResponse(String id, String code, String tier) {
    }

    public record HealthResponse(boolean ok, String service, boolean database) {
    }

    public record ErrorResponse(String error) {
    }
}
