# ML-DSA-44 verifier

**Scheme:** ML-DSA-44 (FIPS 204), lattice-based (module), NIST's primary post-quantum signature
standard.
**Status:** implemented, written for provably.fast's ML-DSA-44 season as its baseline.

`MlDsa44Verifier::verify` is ML-DSA.Verify (FIPS 204, Algorithm 3: the pure variant, with the
empty context string) over this felt encoding:

- the message is the transaction hash, a felt, signed as its 32 big-endian bytes, so
  M' = 0x00 || 0x00 || M;
- the public key (1,312 bytes) and the signature (2,420 bytes) are packed 31 bytes per felt,
  little-endian within each felt, the last felt holding the remainder: 43 and 79 felts. A felt with
  any bit set above its bytes is malformed, so every key and signature has exactly one encoding.

Any FIPS 204 signer makes valid signatures: sign the 32 bytes with an empty context.

| Module | FIPS 204 |
|---|---|
| `encoding.cairo` | the felt encoding above, and M' |
| `keccak.cairo` | SHAKE-128 and SHAKE-256 (FIPS 202) on the Keccak-f[1600] permutation of this repository's Falcon crate |
| `ntt.cairo` | NTT and inverse NTT (Algorithms 41, 42) with lazy felt252 reduction, and the row product of step 8 |
| `packing.cairo` | pkDecode and sigDecode's unpacking (Algorithms 23, 27), HintBitUnpack's checks (21), UseHint (40), w1Encode (28) |
| `sampling.cairo` | ExpandA with RejNTTPoly (32, 30) and SampleInBall (29) |
| `verify.cairo` | ML-DSA.Verify_internal (8) on M', and its external-mu form |

## Tests

- `tests/acvp.cairo`: NIST's ACVP sigVer vectors for ML-DSA-44 (ACVP-Server,
  `gen-val/json-files/ML-DSA-sigVer-FIPS204`): the pure external interface with contexts, the
  internal interface and external mu, 45 cases with NIST's verdicts.
- `tests/felts.cairo`: the felt interface on keys from an independent signer: valid signatures,
  tamperings, every malformed encoding, malformed hints, and z at and around its norm bound.
- `tests/bench.cairo`: one verification and its baseline.

## Current efficiency

| Measurement | L2 gas |
|---|--:|
| one verification (`bench_verify_ml_dsa_44` minus `bench_baseline_ml_dsa_44`) | 618,101,153 |

Keccak-f[1600] dominates: a verification runs 99 permutations (80 of them in ExpandA's SHAKE-128),
about 3.1M gas each. The other large costs are the 13 NTTs, the felt decoding and the absorbing.
Starknet's validation limit is 100M gas.
