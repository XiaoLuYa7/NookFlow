package com.nookflow.license.api;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import java.util.List;

public final class PaymentApiModels {
    private PaymentApiModels() {
    }

    public record ProductResponse(
            boolean paymentEnabled,
            String productCode,
            String productName,
            int amountCents,
            String currency,
            List<String> channels
    ) {
    }

    public record CreateCheckoutRequest(
            @NotBlank @Email String email,
            @NotBlank @Pattern(regexp = "alipay|wxpay") String channel
    ) {
    }

    public record CheckoutResponse(
            String orderNo,
            String checkoutToken,
            String redirectUrl,
            long expiresAt
    ) {
    }

    public record OrderStatusResponse(
            String orderNo,
            String status,
            int amountCents,
            String currency,
            String channel,
            String activationCode,
            Long paidAt
    ) {
    }
}
