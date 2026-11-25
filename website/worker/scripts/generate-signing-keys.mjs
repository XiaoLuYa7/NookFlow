import { generateKeyPairSync } from "node:crypto";

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "prime256v1"
});

const privateJwk = privateKey.export({ format: "jwk" });
const publicJwk = publicKey.export({ format: "jwk" });
const x = Buffer.from(publicJwk.x, "base64url");
const y = Buffer.from(publicJwk.y, "base64url");
const x963 = Buffer.concat([Buffer.from([0x04]), x, y]);

console.log("LICENSE_SIGNING_PRIVATE_JWK=");
console.log(JSON.stringify(privateJwk));
console.log("\nNookFlowLicensePublicKey (base64 X9.63)=");
console.log(x963.toString("base64"));
