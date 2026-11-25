package com.nookflow.license.payment;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nookflow.license.config.PaymentProperties;
import com.nookflow.license.delivery.LicenseMailOutbox;
import com.nookflow.license.service.LicenseService;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;

final class PaymentReturnUrlTest {
    @Test
    void checkoutUsesSingleReturnParameter() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PaymentProperties properties = new PaymentProperties(
                true, "https://pay.example", "1148", "private", "public", "encryption",
                "https://nookflow.luckysoft.cn", 10, 30, 600, 8
        );
        YkmPaymentClient provider = mock(YkmPaymentClient.class);
        when(jdbc.queryForObject(
                eq("SELECT id FROM products WHERE code = ? AND status = 'ACTIVE' LIMIT 1"),
                eq(Long.class), eq("NOOKFLOW_PRO")
        )).thenReturn(1L);
        when(provider.createRedirect(anyMap())).thenReturn("https://pay.example/submit");

        PaymentService service = new PaymentService(
                jdbc,
                mock(LicenseService.class),
                properties,
                mock(PaymentCrypto.class),
                provider,
                mock(LicenseMailOutbox.class),
                mock(TransactionTemplate.class),
                Clock.fixed(Instant.ofEpochMilli(1_800_000_000_000L), ZoneOffset.UTC)
        );

        service.createCheckout("USER@example.com", "alipay", "127.0.0.1");

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> request = ArgumentCaptor.forClass(Map.class);
        verify(provider).createRedirect(request.capture());
        assertThat(request.getValue().get("return_url"))
                .startsWith("https://nookflow.luckysoft.cn/?payment_return=NF")
                .doesNotContain("&");
    }
}
