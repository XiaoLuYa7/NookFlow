package com.nookflow.license.payment;

import com.nookflow.license.api.ApiException;
import com.nookflow.license.api.PaymentApiModels.CheckoutResponse;
import com.nookflow.license.api.PaymentApiModels.OrderStatusResponse;
import com.nookflow.license.api.PaymentApiModels.ProductResponse;
import com.nookflow.license.config.PaymentProperties;
import com.nookflow.license.delivery.LicenseMailOutbox;
import com.nookflow.license.service.LicenseService;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Clock;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public final class PaymentService {
    private static final String PRODUCT_CODE = "NOOKFLOW_PRO";

    private final JdbcTemplate jdbc;
    private final LicenseService licenses;
    private final PaymentProperties properties;
    private final PaymentCrypto crypto;
    private final YkmPaymentClient provider;
    private final LicenseMailOutbox mailOutbox;
    private final TransactionTemplate transactions;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    @Autowired
    public PaymentService(
            JdbcTemplate jdbc,
            LicenseService licenses,
            PaymentProperties properties,
            PaymentCrypto crypto,
            YkmPaymentClient provider,
            LicenseMailOutbox mailOutbox,
            TransactionTemplate transactions
    ) {
        this(jdbc, licenses, properties, crypto, provider, mailOutbox, transactions, Clock.systemUTC());
    }

    PaymentService(
            JdbcTemplate jdbc,
            LicenseService licenses,
            PaymentProperties properties,
            PaymentCrypto crypto,
            YkmPaymentClient provider,
            LicenseMailOutbox mailOutbox,
            TransactionTemplate transactions,
            Clock clock
    ) {
        this.jdbc = jdbc;
        this.licenses = licenses;
        this.properties = properties;
        this.crypto = crypto;
        this.provider = provider;
        this.mailOutbox = mailOutbox;
        this.transactions = transactions;
        this.clock = clock;
    }

    public ProductResponse product() {
        return new ProductResponse(
                properties.enabled(), PRODUCT_CODE, "NookFlow Pro",
                properties.productPriceCents(), "CNY", List.of("alipay", "wxpay")
        );
    }

    public CheckoutResponse createCheckout(String email, String channel, String clientIp) {
        requireEnabled();
        String normalizedChannel = normalizeChannel(channel);
        String normalizedEmail = email.trim().toLowerCase(Locale.ROOT);
        long now = clock.millis();
        long expiresAt = now + properties.orderExpiryMinutes() * 60_000L;
        String id = UUID.randomUUID().toString();
        String orderNo = newOrderNo(now);
        String checkoutToken = randomToken();
        Long productId = jdbc.queryForObject(
                "SELECT id FROM products WHERE code = ? AND status = 'ACTIVE' LIMIT 1",
                Long.class,
                PRODUCT_CODE
        );
        jdbc.update("""
                INSERT INTO payment_orders
                    (id, order_no, product_id, amount_cents, currency, email, channel, status,
                     checkout_token_hash, expires_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'CNY', ?, ?, 'PENDING', ?, ?, ?, ?)
                """, id, orderNo, productId, properties.productPriceCents(), normalizedEmail,
                normalizedChannel, PaymentCrypto.sha256(checkoutToken), expiresAt, now, now);

        try {
            Map<String, String> request = new LinkedHashMap<>();
            request.put("pid", properties.merchantId());
            request.put("type", normalizedChannel);
            request.put("out_trade_no", orderNo);
            request.put("notify_url", publicUrl("/api/payments/ykm/notify"));
            request.put("return_url", publicUrl("/?payment_return=" + urlEncode(orderNo)));
            request.put("name", "NookFlow Pro");
            request.put("money", money(properties.productPriceCents()));
            request.put("timestamp", Long.toString(clock.instant().getEpochSecond()));
            String redirectUrl = provider.createRedirect(request);
            return new CheckoutResponse(orderNo, checkoutToken, redirectUrl, expiresAt);
        } catch (RuntimeException error) {
            jdbc.update("""
                    UPDATE payment_orders SET status = 'FAILED', updated_at = ?
                    WHERE id = ? AND status = 'PENDING' AND provider_trade_no IS NULL
                    """, clock.millis(), id);
            throw error;
        }
    }

    public OrderStatusResponse status(String orderNo, String checkoutToken) {
        requireEnabled();
        OrderRow order = authorizedOrder(orderNo, checkoutToken, false);
        String code = order.encryptedCode() == null
                ? null
                : crypto.decryptActivationCode(order.orderNo(), order.encryptedCode());
        if (code != null && order.firstViewedAt() == null) {
            jdbc.update("""
                    UPDATE license_deliveries SET first_viewed_at = ?, updated_at = ?
                    WHERE order_id = ? AND first_viewed_at IS NULL
                    """, clock.millis(), clock.millis(), order.id());
        }
        if (code != null) {
            mailOutbox.enqueue(order.id(), order.email(), clock.millis());
        }
        return response(order, code);
    }

    public OrderStatusResponse refresh(String orderNo, String checkoutToken) {
        requireEnabled();
        OrderRow order = authorizedOrder(orderNo, checkoutToken, false);
        if (order.status().equals("PENDING") && claimProviderCheck(order.id())) {
            var result = provider.query(order.orderNo());
            if (result.status() == 1) {
                fulfill(
                        order.orderNo(), result.tradeNo(), result.channel(), result.money(),
                        "query|" + order.orderNo() + "|" + result.tradeNo()
                );
            } else if (result.status() == 2) {
                jdbc.update("""
                        UPDATE payment_orders SET status = 'REFUNDED', updated_at = ?
                        WHERE id = ? AND status IN ('PENDING', 'PAID', 'LICENSE_ISSUED')
                        """, clock.millis(), order.id());
            }
        }
        return status(orderNo, checkoutToken);
    }

    public void processNotification(Map<String, String> parameters) {
        requireEnabled();
        if (!crypto.verify(parameters)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_signature");
        }
        if (!properties.merchantId().equals(parameters.get("pid"))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_merchant");
        }
        assertTimestamp(parameters.get("timestamp"));
        if (!"TRADE_SUCCESS".equals(parameters.get("trade_status"))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_status");
        }
        String orderNo = required(parameters, "out_trade_no");
        String tradeNo = required(parameters, "trade_no");
        String channel = required(parameters, "type");
        String amount = required(parameters, "money");
        String eventHash = PaymentCrypto.sha256(tradeNo + "|" + orderNo + "|TRADE_SUCCESS");
        fulfill(orderNo, tradeNo, channel, amount, eventHash);
    }

    private void fulfill(String orderNo, String tradeNo, String channel, String amount, String eventIdentity) {
        transactions.executeWithoutResult(ignored -> {
            OrderRow order = orderForUpdate(orderNo);
            assertPaymentMatches(order, channel, amount);
            if (order.status().equals("LICENSE_ISSUED")) {
                recordEvent(eventIdentity, orderNo, tradeNo, "already_issued");
                return;
            }
            if (order.status().equals("REFUNDED") || order.status().equals("CLOSED")) {
                throw new ApiException(HttpStatus.CONFLICT, "order_not_payable");
            }
            var license = licenses.createLicense("payment:" + orderNo);
            long now = clock.millis();
            String protectedCode = crypto.encryptActivationCode(orderNo, license.code());
            jdbc.update("""
                    INSERT INTO license_deliveries (order_id, encrypted_code, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """, order.id(), protectedCode, now, now);
            jdbc.update("""
                    UPDATE payment_orders
                    SET provider_trade_no = ?, status = 'LICENSE_ISSUED', license_id = ?,
                        paid_at = ?, updated_at = ?
                    WHERE id = ?
                    """, tradeNo, license.id(), now, now, order.id());
            mailOutbox.enqueue(order.id(), order.email(), now);
            recordEvent(eventIdentity, orderNo, tradeNo, "license_issued");
        });
    }

    private OrderRow authorizedOrder(String orderNo, String checkoutToken, boolean lock) {
        if (orderNo == null || orderNo.isBlank() || checkoutToken == null || checkoutToken.isBlank()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "order_not_found");
        }
        OrderRow order = queryOrder(orderNo, lock);
        byte[] expected = order.checkoutTokenHash().getBytes(StandardCharsets.US_ASCII);
        byte[] supplied = PaymentCrypto.sha256(checkoutToken).getBytes(StandardCharsets.US_ASCII);
        if (!MessageDigest.isEqual(expected, supplied)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "order_not_found");
        }
        return order;
    }

    private OrderRow orderForUpdate(String orderNo) {
        return queryOrder(orderNo, true);
    }

    private OrderRow queryOrder(String orderNo, boolean lock) {
        String suffix = lock ? " FOR UPDATE" : "";
        return jdbc.query("""
                SELECT o.id, o.order_no, o.email, o.amount_cents, o.currency, o.channel, o.status,
                       o.checkout_token_hash, o.paid_at, d.encrypted_code, d.first_viewed_at
                FROM payment_orders o
                LEFT JOIN license_deliveries d ON d.order_id = o.id
                WHERE o.order_no = ? LIMIT 1
                """ + suffix, (result, row) -> new OrderRow(
                result.getString("id"), result.getString("order_no"), result.getInt("amount_cents"),
                result.getString("email"), result.getString("currency"), result.getString("channel"),
                result.getString("status"),
                result.getString("checkout_token_hash"), result.getObject("paid_at", Long.class),
                result.getString("encrypted_code"), result.getObject("first_viewed_at", Long.class)
        ), orderNo).stream().findFirst().orElseThrow(
                () -> new ApiException(HttpStatus.NOT_FOUND, "order_not_found")
        );
    }

    private boolean claimProviderCheck(String orderId) {
        long now = clock.millis();
        long cutoff = now - properties.providerQueryCooldownSeconds() * 1000L;
        return jdbc.update("""
                UPDATE payment_orders SET last_provider_check_at = ?, updated_at = ?
                WHERE id = ? AND status = 'PENDING'
                  AND (last_provider_check_at IS NULL OR last_provider_check_at < ?)
                """, now, now, orderId, cutoff) == 1;
    }

    private void assertPaymentMatches(OrderRow order, String channel, String amount) {
        if (!order.channel().equals(normalizeChannel(channel))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "payment_channel_mismatch");
        }
        if (parseCents(amount) != order.amountCents()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "payment_amount_mismatch");
        }
    }

    private void recordEvent(String identity, String orderNo, String tradeNo, String result) {
        String payloadHash = PaymentCrypto.sha256(orderNo + "|" + tradeNo + "|" + result);
        try {
            jdbc.update("""
                    INSERT INTO payment_events
                        (event_hash, order_no, provider_trade_no, payload_hash, result, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, PaymentCrypto.sha256(identity), orderNo, tradeNo, payloadHash, result, clock.millis());
        } catch (DuplicateKeyException ignored) {
            // Provider notifications are retried; the order lock is the source of truth.
        }
    }

    private void assertTimestamp(String value) {
        if (value == null || value.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_timestamp");
        }
        try {
            long timestamp = Long.parseLong(value);
            long difference = Math.abs(clock.instant().getEpochSecond() - timestamp);
            if (difference > properties.timestampSkewSeconds()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "expired_payment_notification");
            }
        } catch (NumberFormatException error) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_timestamp");
        }
    }

    private OrderStatusResponse response(OrderRow order, String code) {
        return new OrderStatusResponse(
                order.orderNo(), order.status(), order.amountCents(), order.currency(),
                order.channel(), code, order.paidAt()
        );
    }

    private void requireEnabled() {
        if (!properties.enabled()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "payment_unavailable");
        }
    }

    private String publicUrl(String path) {
        String base = properties.publicBaseUrl().trim();
        if (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        return base + path;
    }

    private String newOrderNo(long now) {
        byte[] suffix = new byte[6];
        random.nextBytes(suffix);
        return "NF" + now + java.util.HexFormat.of().formatHex(suffix).toUpperCase(Locale.ROOT);
    }

    private String randomToken() {
        byte[] value = new byte[32];
        random.nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    private static String normalizeChannel(String channel) {
        if (!"alipay".equals(channel) && !"wxpay".equals(channel)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_channel");
        }
        return channel;
    }

    private static int parseCents(String amount) {
        try {
            return new BigDecimal(amount).movePointRight(2).setScale(0, RoundingMode.UNNECESSARY).intValueExact();
        } catch (Exception error) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_amount");
        }
    }

    private static String money(int cents) {
        return BigDecimal.valueOf(cents, 2).toPlainString();
    }

    private static String required(Map<String, String> parameters, String name) {
        String value = parameters.get(name);
        if (value == null || value.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_payment_notification");
        }
        return value;
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private record OrderRow(
            String id,
            String orderNo,
            int amountCents,
            String email,
            String currency,
            String channel,
            String status,
            String checkoutTokenHash,
            Long paidAt,
            String encryptedCode,
            Long firstViewedAt
    ) {
    }
}
