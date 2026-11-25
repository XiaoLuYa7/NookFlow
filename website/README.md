# NookFlow website and license service

This directory contains the static NookFlow website and a self-hosted V1
license service built with Spring Boot 3 and MySQL 8.

## Components

- `public/`: static website and DMG download.
- `server/`: activation API. The database stores keyed hashes of activation
  codes and device public-key hashes, never plaintext activation codes or Mac
  hardware serial numbers.
- `deploy/`: Docker Compose, Nginx, manual license issuance, and daily backup.

## API

- `GET /api/health`
- `POST /api/activate`
- `POST /api/validate`
- `POST /api/deactivate`
- `POST /api/admin/licenses`
- `GET /api/store/product`
- `POST /api/store/orders`
- `GET /api/store/orders/{orderNo}`
- `POST /api/store/orders/{orderNo}/refresh`
- `GET /api/payments/ykm/notify`

The device signs every request with a private key stored as
`AfterFirstUnlockThisDeviceOnly` in the macOS Keychain. The server returns a
P-256 signed token which the app verifies locally before unlocking Pro.

## Local website preview

```bash
npm run preview
```

## Server deployment

1. Copy `server/`, `deploy/`, and `public/` to the host.
2. Create `deploy/.env` with strong values for:
   `DATABASE_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `LICENSE_CODE_PEPPER`,
   `LICENSE_SIGNING_PRIVATE_JWK`, and `ADMIN_TOKEN`.
3. Install MySQL 8, Java 17, and Nginx. Docker Compose remains available as an
   alternative for hosts with reliable Docker Hub access.
4. Build `server/` and install the JAR plus `deploy/nookflow-license.service`.
5. Install `deploy/nginx.conf` as the Nginx site and copy `public/` to
   `/var/www/nookflow/`.

Create a one-device activation code on the server:

```bash
/opt/nookflow/deploy/create-license.sh order-1001
```

The plaintext code is returned once. Only its HMAC-SHA256 hash is stored.

## YKM payment checkout

The website can create Alipay or WeChat Pay checkout orders through the YKM V2
RSA API. Payment is disabled by default, so the existing website and license
API continue to work before merchant credentials are configured.

For Docker Compose, add these values to `deploy/.env`. For the bundled systemd
service, add the same values to `/etc/nookflow/license.env`:

```dotenv
PAYMENT_ENABLED='true'
PUBLIC_BASE_URL='https://your-public-domain.example'
YKM_API_URL='https://pay.ykmcn.com'
YKM_MERCHANT_ID='your-merchant-id'
YKM_MERCHANT_PRIVATE_KEY='your-PKCS8-private-key'
YKM_PLATFORM_PUBLIC_KEY='the-platform-X509-public-key'
PAYMENT_DELIVERY_ENCRYPTION_KEY='a-base64-encoded-32-byte-key'
NOOKFLOW_PRO_PRICE_CENTS='990'
```

Generate the activation-code delivery key once and keep it backed up:

```bash
openssl rand -base64 32
```

`PUBLIC_BASE_URL` must be the public HTTPS origin. The provider notification URL
is `${PUBLIC_BASE_URL}/api/payments/ykm/notify`. The server verifies the RSA
signature, merchant ID, notification timestamp, payment channel, exact amount,
and successful trade state before issuing a license. Provider retries are
idempotent and cannot issue a second license for the same order.

Set `NOOKFLOW_PRO_PRICE_CENTS='990'` for the ¥9.90 production price, restart the
license service, open the website, and create an order from the Pro section.
Confirm that the browser returns to the website, an activation code appears,
and the matching `payment_orders` row reaches `LICENSE_ISSUED`. Increase the
price only after this complete callback flow has been verified.

Do not put merchant private keys in `public/`, JavaScript, Git, screenshots, or
support messages. Configure them directly in the server environment file.

## Production requirements

Before accepting real activation codes, point a domain at the server and enable
HTTPS. The public DMG must also be Developer ID signed and notarized before it
is promoted as a production download.

## Publishing app updates

The website build uses Sparkle 2.9.6 with the stable bundle identifier
`cn.luckysoft.NookFlow`. Its signed feed is published at
`https://nookflow.luckysoft.cn/appcast.xml`.

For every release:

1. Increase both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode
   target. The build number must always increase.
2. Archive with the same Developer ID Application identity, export, notarize,
   and staple the application before creating the DMG.
3. Put the versioned DMG in `public/downloads/`. Do not replace an older file
   with different bytes under the same URL.
4. Add all three release-note files beside the DMG. Their basename must exactly
   match the DMG so Sparkle can associate them with that version:

   - `NookFlow-1.0.4.html`: default/fallback release notes.
   - `NookFlow-1.0.4.zh.html`: Chinese release notes.
   - `NookFlow-1.0.4.en.html`: English release notes.

   Keep the notes concise and user-facing. Include new features, improvements,
   fixes, and any action the user must take. The publishing script rejects a
   release when any of these files is missing or empty.
5. Locate Sparkle's `generate_appcast` executable in the resolved Swift package
   artifact, then pass the release version to the script:

   ```bash
   SPARKLE_GENERATE_APPCAST='/path/to/generate_appcast' ./generate-appcast.sh 1.0.4
   ```

6. Upload the new DMG, all three release-note files, and `public/appcast.xml`
   together. Verify the DMG, appcast, and localized release-note HTTPS URLs
   before announcing the release.

Sparkle's private EdDSA key is stored only in the login Keychain under the
default `ed25519` account. Back it up securely with Sparkle's `generate_keys -x`
command before the first public release. Never commit or upload the exported
private-key file. Losing that key prevents existing installations from trusting
future updates; changing `SUPublicEDKey` in the app does not repair older builds.
