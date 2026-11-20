// PF-13: ML-DSA-44 vectors from @noble/post-quantum (the kit's signer), in the on-chain felt layout
// of signer/mldsa_adapter.mjs. Deterministic (fixed seeds, no signing randomness), so a rerun
// reproduces vectors.json byte for byte.
//
//   node bench/pf13/noble_vectors.mjs > bench/pf13/vectors.json   (after `npm install` in signer/)
import { createHash } from "node:crypto";
import { hashBytes, ml_dsa44, publicKeyFelts, signatureFelts, signTxHash } from "../../signer/mldsa_adapter.mjs";

const FELT_PRIME = 2n ** 251n + 17n * 2n ** 192n + 1n;
const label = (...parts) => createHash("sha512").update(["starknet-pq-account/pf13-noble-v1", ...parts].join("|")).digest();
const hex = (v) => "0x" + BigInt(v).toString(16);

const vectors = [];
for (let key = 0; key < 3; key++) {
  const { publicKey, secretKey } = ml_dsa44.keygen(new Uint8Array(label("key", key).subarray(0, 32)));
  const messages = [0n, FELT_PRIME - 1n];
  for (let i = 0; i < 2; i++) messages.push(BigInt("0x" + label("msg", key, i).toString("hex")) % FELT_PRIME);
  for (const message of messages) {
    const sig = signTxHash(message, secretKey);
    if (!ml_dsa44.verify(sig, hashBytes(message), publicKey)) throw new Error("noble rejects its own signature");
    vectors.push({ id: vectors.length, category: "valid", source: "noble", key: `noble-${key}`, message: hex(message),
      public_key: publicKeyFelts(publicKey).map(hex), signature: signatureFelts(sig).map(hex) });
  }
}
console.log(JSON.stringify({ noble: "@noble/post-quantum 0.6.1", vectors }, null, 1));
