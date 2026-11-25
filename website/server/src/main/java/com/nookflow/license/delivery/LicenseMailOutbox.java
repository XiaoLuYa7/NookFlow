package com.nookflow.license.delivery;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public final class LicenseMailOutbox {
    private final JdbcTemplate jdbc;

    public LicenseMailOutbox(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void enqueue(String orderId, String recipient, long now) {
        jdbc.update("""
                INSERT IGNORE INTO license_email_outbox
                    (order_id, recipient, status, attempts, next_attempt_at, created_at, updated_at)
                VALUES (?, ?, 'PENDING', 0, ?, ?, ?)
                """, orderId, recipient, now, now, now);
    }
}
