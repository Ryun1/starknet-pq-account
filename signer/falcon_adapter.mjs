// Turns standard Falcon-512 and Falcon-1024 keys and signatures from @noble/post-quantum (pure
// JS, runs in the browser) into the on-chain layout of the SHAKE-256 hint verifiers:
//   public key: pack(NTT(h)) in falcon.py's NTT ordering        (29 felts; 57 at n = 1024)
//   signature:  pack(s2 mod q) || salt_a || salt_b || pack(s2 * h mod q)  (60; 116 at n = 1024)
// The message signed is the 32-byte little-endian encoding of the transaction hash, which is
// exactly what the on-chain SHAKE-256 hash-to-point absorbs after the 40-byte salt. n is read from
// the key's and the signature's header byte; the NTT needs the roots for that n
// (falcon_ntt_roots.json stops at 512, falcon1024_ntt_roots.json goes to 1024).
import { falcon512, falcon1024 } from "@noble/post-quantum/falcon.js";

export const Q = 12289;
const SQR1 = 1479; // a square root of -1 mod q, falcon.py ntt.py
// Falcon spec 3.11: header bytes are tag + log2(n); key = header || 14-bit h.
const PARAMS = {
  512: { pkHeader: 0x09, pkBytes: 897, sigHeader: 0x39, scheme: falcon512 },
  1024: { pkHeader: 0x0a, pkBytes: 1793, sigHeader: 0x3a, scheme: falcon1024 },
};

export function hashToMessage(txHash) {
  let v = BigInt(txHash);
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) { out[i] = Number(v & 0xffn); v >>= 8n; }
  return out;
}

export function decodePublicKey(pk) {
  const N = pk[0] === 0x0a ? 1024 : 512;
  if (pk.length !== PARAMS[N].pkBytes || pk[0] !== PARAMS[N].pkHeader) throw new Error("expected a Falcon-512 or Falcon-1024 public key");
  const h = new Array(N);
  let acc = 0, bits = 0, pos = 1;
  for (let i = 0; i < N; i++) {
    while (bits < 14) { acc = (acc << 8) | pk[pos++]; bits += 8; }
    bits -= 14;
    h[i] = (acc >>> bits) & 0x3fff;
    acc &= (1 << bits) - 1;
    if (h[i] >= Q) throw new Error("public key coefficient out of range");
  }
  return h;
}

// Falcon Decompress (spec Algorithm 18).
export function decodeSignature(sig) {
  const N = sig[0] === 0x3a ? 1024 : 512;
  if (sig[0] !== PARAMS[N].sigHeader) throw new Error("expected a Falcon-512 or Falcon-1024 detached signature");
  const nonce = sig.slice(1, 41);
  const data = sig.slice(41);
  const s2 = new Array(N);
  let acc = 0, bits = 0, pos = 0;
  const read = (n) => {
    while (bits < n) { if (pos >= data.length) throw new Error("truncated signature"); acc = (acc << 8) | data[pos++]; bits += 8; }
    bits -= n;
    const v = (acc >>> bits) & ((1 << n) - 1);
    acc &= (1 << bits) - 1;
    return v;
  };
  for (let i = 0; i < N; i++) {
    const sign = read(1);
    const low = read(7);
    let high = 0;
    while (!read(1)) high++;
    const v = low | (high << 7);
    if (sign && v === 0) throw new Error("negative zero");
    s2[i] = sign ? -v : v;
  }
  return { nonce, s2 };
}

export function makeNtt(roots) {
  const split = (f) => [f.filter((_, i) => i % 2 === 0), f.filter((_, i) => i % 2 === 1)];
  const ntt = (f) => {
    const n = f.length;
    if (n === 2) return [(f[0] + SQR1 * f[1]) % Q, ((f[0] - SQR1 * f[1]) % Q + Q) % Q];
    const [f0, f1] = split(f);
    const a = ntt(f0), b = ntt(f1);
    const w = roots[n];
    const out = new Array(n);
    for (let i = 0; i < n / 2; i++) {
      const t = (w[2 * i] * b[i]) % Q;
      out[2 * i] = (a[i] + t) % Q;
      out[2 * i + 1] = ((a[i] - t) % Q + Q) % Q;
    }
    return out;
  };
  return ntt;
}

// Base q, nine values per 128-bit half, first value least significant; the last felt takes the
// rest: eight low at n = 512 (pq-accounts' falcon_signer.py pack_512, 29 felts), nine low and
// seven high at n = 1024 (the Falcon-1024 lane's pack_1024, 57 felts).
export function pack(vals) {
  if (!PARAMS[vals.length] || vals.some((v) => v < 0 || v >= Q)) throw new Error("expected 512 or 1024 values in [0, q)");
  const half = (chunk) => chunk.reduceRight((acc, c) => acc * BigInt(Q) + BigInt(c), 0n);
  const felts = [];
  for (let j = 0; j < vals.length; j += 18) {
    felts.push(half(vals.slice(j, j + 9)) + (half(vals.slice(j + 9, j + 18)) << 128n));
  }
  return felts;
}

export function pack512(vals) {
  if (vals.length !== 512) throw new Error("expected 512 values in [0, q)");
  return pack(vals);
}

// s2 * h in Z_q[x]/(x^n + 1), schoolbook (fine for one signature).
export function mulNegacyclic(a, b) {
  const N = a.length;
  const out = new Array(N).fill(0);
  for (let i = 0; i < N; i++) {
    if (a[i] === 0) continue;
    for (let j = 0; j < N; j++) {
      const k = i + j;
      const p = a[i] * b[j];
      if (k < N) out[k] += p; else out[k - N] -= p;
    }
  }
  return out.map((v) => ((v % Q) + Q) % Q);
}

const leInt = (bytes) => bytes.reduceRight((acc, b) => (acc << 8n) | BigInt(b), 0n);

export function publicKeyFelts(pk, ntt) {
  return pack(ntt(decodePublicKey(pk)));
}

export function signatureFelts(sig, pk) {
  const { nonce, s2 } = decodeSignature(sig);
  const h = decodePublicKey(pk);
  const s2modq = s2.map((v) => ((v % Q) + Q) % Q);
  const hint = mulNegacyclic(s2modq, h);
  if (s2.length !== h.length) throw new Error("signature and public key are for different n");
  return [...pack(s2modq), leInt(nonce.slice(0, 20)), leInt(nonce.slice(20)), ...pack(hint)];
}

// n from the secret key's header byte (0x59 at n = 512, 0x5a at n = 1024).
export function signTxHash(txHash, secretKey, n = secretKey[0] === 0x5a ? 1024 : 512) {
  return PARAMS[n].scheme.sign(hashToMessage(txHash), secretKey);
}

export { falcon512, falcon1024 };
