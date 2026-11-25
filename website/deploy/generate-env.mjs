import { chmod, readFile, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { resolve } from "node:path";

const websiteRoot = resolve(import.meta.dirname, "..");
const sourcePath = resolve(websiteRoot, ".dev.vars");
const targetPath = resolve(import.meta.dirname, ".env");
const source = await readFile(sourcePath, "utf8");
const values = new Map();

for (const line of source.split(/\r?\n/)) {
  const separator = line.indexOf("=");
  if (separator < 1) continue;
  values.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
}

for (const name of ["LICENSE_CODE_PEPPER", "LICENSE_SIGNING_PRIVATE_JWK", "ADMIN_TOKEN"]) {
  if (!values.get(name)) throw new Error(`${name} is missing from ${sourcePath}`);
}

const secret = () => randomBytes(36).toString("base64url");
const quote = value => `'${String(value).replaceAll("'", "'\\''")}'`;
const output = [
  `DATABASE_URL=${quote("jdbc:mysql://127.0.0.1:3306/nookflow?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC&useSSL=false&allowPublicKeyRetrieval=true")}`,
  `DATABASE_USER=${quote("nookflow")}`,
  `DATABASE_PASSWORD=${quote(secret())}`,
  `MYSQL_ROOT_PASSWORD=${quote(secret())}`,
  `LICENSE_CODE_PEPPER=${quote(values.get("LICENSE_CODE_PEPPER"))}`,
  `LICENSE_SIGNING_PRIVATE_JWK=${quote(values.get("LICENSE_SIGNING_PRIVATE_JWK"))}`,
  `ADMIN_TOKEN=${quote(values.get("ADMIN_TOKEN"))}`,
  `PAYMENT_ENABLED=${quote("false")}`,
  `PUBLIC_BASE_URL=${quote("")}`,
  `YKM_API_URL=${quote("https://pay.ykmcn.com")}`,
  `YKM_MERCHANT_ID=${quote("")}`,
  `YKM_MERCHANT_PRIVATE_KEY=${quote("")}`,
  `YKM_PLATFORM_PUBLIC_KEY=${quote("")}`,
  `PAYMENT_DELIVERY_ENCRYPTION_KEY=${quote(randomBytes(32).toString("base64"))}`,
  `NOOKFLOW_PRO_PRICE_CENTS=${quote("990")}`,
  ""
].join("\n");

await writeFile(targetPath, output, { encoding: "utf8", mode: 0o600 });
await chmod(targetPath, 0o600);
console.log(`Created ${targetPath} with mode 0600`);
