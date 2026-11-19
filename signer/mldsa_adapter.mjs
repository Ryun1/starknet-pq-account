// ML-DSA-44 (FIPS 204) in the felt encoding of vendor/cairo-pq-verifiers/crates/ml_dsa_44 (PF-13):
// keys and signatures packed 31 bytes per felt, little-endian within each felt, the last felt
// holding the remainder (1,312 B -> 43 felts, 2,420 B -> 79). The message is the transaction hash
// as 32 BIG-endian bytes, pure ML-DSA with the empty context. (Falcon signs the little-endian
// bytes; this is the one place the two schemes differ.)
import { ml_dsa44 } from "@noble/post-quantum/ml-dsa.js";

export { ml_dsa44 };

export function bytesToFelts(bytes) {
  const felts = [];
  for (let i = 0; i < bytes.length; i += 31) {
    let x = 0n;
    for (let j = Math.min(i + 31, bytes.length) - 1; j >= i; j--) x = (x << 8n) | BigInt(bytes[j]);
    felts.push(x);
  }
  return felts;
}

export const publicKeyFelts = (publicKey) => bytesToFelts(publicKey);
export const signatureFelts = (signature) => bytesToFelts(signature);

export function hashBytes(txHash) {
  const hex = BigInt(txHash).toString(16).padStart(64, "0");
  if (hex.length !== 64) throw new Error("hash does not fit 32 bytes");
  return Uint8Array.from(hex.match(/../g), (b) => parseInt(b, 16));
}

/** ML-DSA-44 signature over the hash, deterministic (no randomness, so fixtures are stable). */
export function signTxHash(txHash, secretKey) {
  return ml_dsa44.sign(hashBytes(txHash), secretKey, { extraEntropy: false });
}
