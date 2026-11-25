CREATE TABLE IF NOT EXISTS products (
    id BIGINT NOT NULL AUTO_INCREMENT,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(120) NOT NULL,
    status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_products_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO products (code, name, status, created_at, updated_at)
SELECT 'NOOKFLOW_PRO', 'NookFlow Pro', 'ACTIVE', UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)) * 1000,
       UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)) * 1000
WHERE NOT EXISTS (SELECT 1 FROM products WHERE code = 'NOOKFLOW_PRO');

CREATE TABLE IF NOT EXISTS licenses (
    id CHAR(36) NOT NULL,
    product_id BIGINT NOT NULL,
    code_hash CHAR(64) NOT NULL,
    tier VARCHAR(32) NOT NULL DEFAULT 'pro',
    status ENUM('ACTIVE', 'REVOKED', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
    max_devices SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    transfer_limit SMALLINT UNSIGNED NOT NULL DEFAULT 3,
    transfer_count SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    note VARCHAR(160) NULL,
    issued_at BIGINT NOT NULL,
    expire_at BIGINT NULL,
    last_verified_at BIGINT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_licenses_code_hash (code_hash),
    KEY idx_licenses_status (status),
    CONSTRAINT fk_licenses_product FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS license_devices (
    id CHAR(36) NOT NULL,
    license_id CHAR(36) NOT NULL,
    device_hash CHAR(64) NOT NULL,
    device_public_key TEXT NOT NULL,
    status ENUM('ACTIVE', 'DEACTIVATED') NOT NULL DEFAULT 'ACTIVE',
    activated_at BIGINT NOT NULL,
    deactivated_at BIGINT NULL,
    last_seen_at BIGINT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_license_devices_license (license_id),
    KEY idx_license_devices_hash (device_hash),
    CONSTRAINT fk_license_devices_license FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS activation_events (
    id BIGINT NOT NULL AUTO_INCREMENT,
    license_id CHAR(36) NOT NULL,
    device_hash CHAR(64) NOT NULL,
    action ENUM('ACTIVATE', 'VALIDATE', 'DEACTIVATE', 'REJECT') NOT NULL,
    created_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    KEY idx_activation_events_license_time (license_id, created_at),
    CONSTRAINT fk_activation_events_license FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_orders (
    id CHAR(36) NOT NULL,
    order_no VARCHAR(64) NOT NULL,
    provider_trade_no VARCHAR(64) NULL,
    product_id BIGINT NOT NULL,
    amount_cents INT UNSIGNED NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'CNY',
    email VARCHAR(254) NOT NULL,
    channel VARCHAR(16) NOT NULL,
    status ENUM('PENDING', 'PAID', 'LICENSE_ISSUED', 'REFUNDED', 'CLOSED', 'FAILED') NOT NULL,
    checkout_token_hash CHAR(64) NOT NULL,
    license_id CHAR(36) NULL,
    last_provider_check_at BIGINT NULL,
    paid_at BIGINT NULL,
    expires_at BIGINT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_payment_orders_order_no (order_no),
    UNIQUE KEY uk_payment_orders_provider_trade_no (provider_trade_no),
    UNIQUE KEY uk_payment_orders_license (license_id),
    KEY idx_payment_orders_status_created (status, created_at),
    CONSTRAINT fk_payment_orders_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT fk_payment_orders_license FOREIGN KEY (license_id) REFERENCES licenses(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_events (
    id BIGINT NOT NULL AUTO_INCREMENT,
    event_hash CHAR(64) NOT NULL,
    order_no VARCHAR(64) NOT NULL,
    provider_trade_no VARCHAR(64) NULL,
    payload_hash CHAR(64) NOT NULL,
    result VARCHAR(32) NOT NULL,
    created_at BIGINT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_payment_events_hash (event_hash),
    KEY idx_payment_events_order_time (order_no, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS license_deliveries (
    order_id CHAR(36) NOT NULL,
    encrypted_code TEXT NOT NULL,
    first_viewed_at BIGINT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_license_deliveries_order FOREIGN KEY (order_id) REFERENCES payment_orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS license_email_outbox (
    order_id CHAR(36) NOT NULL,
    recipient VARCHAR(254) NOT NULL,
    status ENUM('PENDING', 'SENDING', 'RETRY', 'SENT', 'FAILED') NOT NULL DEFAULT 'PENDING',
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    next_attempt_at BIGINT NOT NULL,
    locked_at BIGINT NULL,
    sent_at BIGINT NULL,
    last_error VARCHAR(500) NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (order_id),
    KEY idx_license_email_due (status, next_attempt_at),
    CONSTRAINT fk_license_email_order FOREIGN KEY (order_id) REFERENCES payment_orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
