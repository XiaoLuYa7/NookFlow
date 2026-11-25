package com.nookflow.license.api;

import static com.nookflow.license.api.PaymentApiModels.CheckoutResponse;
import static com.nookflow.license.api.PaymentApiModels.CreateCheckoutRequest;
import static com.nookflow.license.api.PaymentApiModels.OrderStatusResponse;
import static com.nookflow.license.api.PaymentApiModels.ProductResponse;

import com.nookflow.license.payment.PaymentService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public final class PaymentController {
    private final PaymentService service;

    public PaymentController(PaymentService service) {
        this.service = service;
    }

    @GetMapping("/store/product")
    ProductResponse product() {
        return service.product();
    }

    @PostMapping("/store/orders")
    CheckoutResponse create(
            @Valid @RequestBody CreateCheckoutRequest request,
            HttpServletRequest httpRequest
    ) {
        return service.createCheckout(request.email(), request.channel(), httpRequest.getRemoteAddr());
    }

    @GetMapping("/store/orders/{orderNo}")
    OrderStatusResponse status(
            @PathVariable String orderNo,
            @RequestHeader("X-Checkout-Token") String checkoutToken
    ) {
        return service.status(orderNo, checkoutToken);
    }

    @PostMapping("/store/orders/{orderNo}/refresh")
    OrderStatusResponse refresh(
            @PathVariable String orderNo,
            @RequestHeader("X-Checkout-Token") String checkoutToken
    ) {
        return service.refresh(orderNo, checkoutToken);
    }

    @GetMapping(value = "/payments/ykm/notify", produces = MediaType.TEXT_PLAIN_VALUE)
    String notify(HttpServletRequest request) {
        Map<String, String> parameters = new LinkedHashMap<>();
        request.getParameterMap().forEach((name, values) -> {
            if (values.length != 1) {
                throw new ApiException(org.springframework.http.HttpStatus.BAD_REQUEST, "invalid_payment_notification");
            }
            parameters.put(name, values[0]);
        });
        service.processNotification(parameters);
        return "success";
    }
}
