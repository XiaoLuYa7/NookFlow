package com.nookflow.license.api;

import static com.nookflow.license.api.ApiModels.CreateLicenseRequest;
import static com.nookflow.license.api.ApiModels.CreatedLicenseResponse;

import com.nookflow.license.config.LicenseProperties;
import com.nookflow.license.service.LicenseService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final LicenseService service;
    private final LicenseProperties properties;

    public AdminController(LicenseService service, LicenseProperties properties) {
        this.service = service;
        this.properties = properties;
    }

    @PostMapping("/licenses")
    CreatedLicenseResponse createLicense(
            @RequestHeader(value = "Authorization", defaultValue = "") String authorization,
            @RequestBody(required = false) CreateLicenseRequest request
    ) {
        byte[] expected = ("Bearer " + properties.adminToken()).getBytes(StandardCharsets.UTF_8);
        byte[] supplied = authorization.getBytes(StandardCharsets.UTF_8);
        if (!MessageDigest.isEqual(expected, supplied)) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "unauthorized");
        }
        var license = service.createLicense(request == null ? null : request.note());
        return new CreatedLicenseResponse(license.id(), license.code(), license.tier());
    }
}
