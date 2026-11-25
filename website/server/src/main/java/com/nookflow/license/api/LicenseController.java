package com.nookflow.license.api;

import static com.nookflow.license.api.ApiModels.ActivationRequest;
import static com.nookflow.license.api.ApiModels.DeactivationResponse;
import static com.nookflow.license.api.ApiModels.HealthResponse;
import static com.nookflow.license.api.ApiModels.LicenseResponse;
import static com.nookflow.license.api.ApiModels.SignedLicenseRequest;

import com.nookflow.license.service.LicenseService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class LicenseController {
    private final LicenseService service;

    public LicenseController(LicenseService service) {
        this.service = service;
    }

    @GetMapping("/health")
    HealthResponse health() {
        boolean database = service.databaseHealthy();
        return new HealthResponse(database, "nookflow-license", database);
    }

    @PostMapping("/activate")
    LicenseResponse activate(@Valid @RequestBody ActivationRequest request) {
        return new LicenseResponse(service.activate(
                request.code(), request.devicePublicKey(), request.timestamp(), request.proof()
        ));
    }

    @PostMapping("/validate")
    LicenseResponse validate(@Valid @RequestBody SignedLicenseRequest request) {
        return new LicenseResponse(service.validate(
                request.signedLicense(), request.devicePublicKey(), request.timestamp(), request.proof()
        ));
    }

    @PostMapping("/deactivate")
    DeactivationResponse deactivate(@Valid @RequestBody SignedLicenseRequest request) {
        service.deactivate(request.signedLicense(), request.devicePublicKey(), request.timestamp(), request.proof());
        return new DeactivationResponse(true);
    }
}
