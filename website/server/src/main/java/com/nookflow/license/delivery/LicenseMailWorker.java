package com.nookflow.license.delivery;

import com.nookflow.license.config.MailDeliveryProperties;
import com.nookflow.license.payment.PaymentCrypto;
import jakarta.annotation.PostConstruct;
import jakarta.mail.internet.MimeMessage;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "nookflow.mail", name = "enabled", havingValue = "true")
public final class LicenseMailWorker {
    private static final Logger log = LoggerFactory.getLogger(LicenseMailWorker.class);
    private static final int BATCH_SIZE = 5;
    private static final long STALE_LOCK_MILLIS = 5 * 60_000L;

    private final JdbcTemplate jdbc;
    private final JavaMailSender mailSender;
    private final PaymentCrypto crypto;
    private final MailDeliveryProperties properties;

    public LicenseMailWorker(
            JdbcTemplate jdbc,
            JavaMailSender mailSender,
            PaymentCrypto crypto,
            MailDeliveryProperties properties
    ) {
        this.jdbc = jdbc;
        this.mailSender = mailSender;
        this.crypto = crypto;
        this.properties = properties;
    }

    @PostConstruct
    void validateConfiguration() {
        if (properties.fromAddress() == null || properties.fromAddress().isBlank()) {
            throw new IllegalStateException("LICENSE_MAIL_FROM is required when license email is enabled");
        }
    }

    @Scheduled(
            initialDelayString = "${nookflow.mail.poll-delay-millis:30000}",
            fixedDelayString = "${nookflow.mail.poll-delay-millis:30000}"
    )
    public void deliverPending() {
        long now = System.currentTimeMillis();
        List<DeliveryRow> deliveries = jdbc.query("""
                SELECT m.order_id, m.recipient, m.attempts, o.order_no, d.encrypted_code
                FROM license_email_outbox m
                JOIN payment_orders o ON o.id = m.order_id
                JOIN license_deliveries d ON d.order_id = m.order_id
                WHERE (m.status IN ('PENDING', 'RETRY') AND m.next_attempt_at <= ?)
                   OR (m.status = 'SENDING' AND m.locked_at < ?)
                ORDER BY m.created_at
                LIMIT ?
                """, (result, row) -> new DeliveryRow(
                result.getString("order_id"),
                result.getString("recipient"),
                result.getInt("attempts"),
                result.getString("order_no"),
                result.getString("encrypted_code")
        ), now, now - STALE_LOCK_MILLIS, BATCH_SIZE);

        for (DeliveryRow delivery : deliveries) {
            deliver(delivery, now);
        }
    }

    private void deliver(DeliveryRow delivery, long now) {
        int attempt = delivery.attempts() + 1;
        int claimed = jdbc.update("""
                UPDATE license_email_outbox
                SET status = 'SENDING', attempts = ?, locked_at = ?, updated_at = ?, last_error = NULL
                WHERE order_id = ?
                  AND ((status IN ('PENDING', 'RETRY') AND next_attempt_at <= ?)
                    OR (status = 'SENDING' AND locked_at < ?))
                """, attempt, now, now, delivery.orderId(), now, now - STALE_LOCK_MILLIS);
        if (claimed != 1) return;

        try {
            String activationCode = crypto.decryptActivationCode(
                    delivery.orderNo(), delivery.encryptedCode()
            );
            sendMessage(delivery.recipient(), delivery.orderNo(), activationCode);
            long sentAt = System.currentTimeMillis();
            jdbc.update("""
                    UPDATE license_email_outbox
                    SET status = 'SENT', sent_at = ?, locked_at = NULL, updated_at = ?
                    WHERE order_id = ? AND status = 'SENDING'
                    """, sentAt, sentAt, delivery.orderId());
            log.info("Activation email delivered for order {}", delivery.orderNo());
        } catch (Exception error) {
            recordFailure(delivery, attempt, error);
        }
    }

    private void sendMessage(String recipient, String orderNo, String activationCode) throws Exception {
        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, false, StandardCharsets.UTF_8.name());
        String senderName = properties.fromName() == null || properties.fromName().isBlank()
                ? "NookFlow"
                : properties.fromName().trim();
        helper.setFrom(properties.fromAddress().trim(), senderName);
        helper.setTo(recipient);
        helper.setSubject("你的 NookFlow Pro 激活码");
        helper.setText("""
                NookFlow Pro 已支付成功。

                激活码：%s
                订单号：%s

                请在 NookFlow 的 Pro 激活页面输入激活码。激活码将绑定首次激活的设备，请勿转发给他人。

                NookFlow
                https://nookflow.luckysoft.cn/
                """.formatted(activationCode, orderNo));
        mailSender.send(message);
    }

    private void recordFailure(DeliveryRow delivery, int attempt, Exception error) {
        long now = System.currentTimeMillis();
        boolean exhausted = attempt >= properties.effectiveMaxAttempts();
        long delaySeconds = Math.min(
                3600L,
                properties.effectiveRetryDelaySeconds() * (1L << Math.min(attempt - 1, 6))
        );
        String reason = error.getClass().getSimpleName() + ": "
                + (error.getMessage() == null ? "mail delivery failed" : error.getMessage());
        if (reason.length() > 500) reason = reason.substring(0, 500);
        jdbc.update("""
                UPDATE license_email_outbox
                SET status = ?, next_attempt_at = ?, locked_at = NULL, last_error = ?, updated_at = ?
                WHERE order_id = ? AND status = 'SENDING'
                """, exhausted ? "FAILED" : "RETRY", now + delaySeconds * 1000L,
                reason, now, delivery.orderId());
        log.warn("Activation email delivery failed for order {} (attempt {})",
                delivery.orderNo(), attempt);
    }

    private record DeliveryRow(
            String orderId,
            String recipient,
            int attempts,
            String orderNo,
            String encryptedCode
    ) {
    }
}
