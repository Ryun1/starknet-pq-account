# Key backup profile v0.2: Falcon-1024 and ML-DSA-44

Status: experimental, unaudited, testnet only (PF-14, PF-13). Profiles v0 and v0.1
([key-backup-v0.md](key-backup-v0.md)) are unchanged; v0.2 only adds a Falcon-1024 key and an
ML-DSA-44 key.

One BIP39 mnemonic, the same BIP39 seed and the same ECDSA profiles (`pq`, `argentx`, `braavos`)
as v0.1. Only the post-quantum key differs:

- `seed48 = HKDF-SHA512(ikm = seed, salt = "starknet-pq-backup-v0.2", info = "falcon-1024/noble/account/i", L = 48)`
- `falcon1024.keygen(seed48)` from [@noble/post-quantum](https://github.com/paulmillr/noble-post-quantum) 0.6.1

As in v0.1, the key is defined by that library's key generation procedure, not by the Falcon
specification, which does not fix one: another implementation given the same 48 bytes may produce
another key. A wallet that restores a v0.2 key must use the same library version or check the
result against the key stored on chain (`get_falcon_public_key`, 57 felts).

`signer/pq_keys.mjs`: `deriveAccountKeys(words, i, ecdsaProfile, "falcon-1024")`; the default,
`"falcon-512"`, is v0.1 and gives the same keys as before. `signer/scheme_switch_check.mjs` checks
both. Key generation takes about 0.25 s in Node.

Test vector (the public BIP39 test mnemonic `abandon` x 11 + `about`, profile `pq`, index 0):

| | |
| --- | --- |
| ECDSA public key | `0x5d97a4a9174d9158c3886717a70112c5e60b17318a1d3ae17f563f1cf8292f4` (same as v0.1) |
| SHA-256 of the 1,793-byte Falcon-1024 public key | `d14527e61098ec1c65435148886c783d064dd193339720d3d5b544b4ecff864a` |

The browser page (`docs/index.html`) restores v0.2 keys when the account's on-chain key is 57 felts,
and its Falcon-1024 demo account is the public demo words at index 1.

## ML-DSA-44 (PF-13)

Same mnemonic, seed and ECDSA profiles; the same salt with another info tag and length:

- `seed32 = HKDF-SHA512(ikm = seed, salt = "starknet-pq-backup-v0.2", info = "ml-dsa-44/fips204/account/i", L = 32)`
- `ML-DSA.KeyGen_internal(seed32)` (FIPS 204, Algorithm 6); in the kit, `ml_dsa44.keygen(seed32)` from
  @noble/post-quantum 0.6.1

Unlike Falcon, FIPS 204 fixes key generation from the seed, so any conforming implementation restores
the same key. `signer/scheme_switch_check.mjs` checks noble against the 25 ML-DSA-44 cases of NIST's
ACVP keyGen vectors (`bench/pf13/acvp_keygen.json`: seeds and key hashes, with the source file's
URL and SHA-256). On chain the key is 43 felts (`get_falcon_public_key`).

`deriveAccountKeys(words, i, ecdsaProfile, "ml-dsa-44")`. The kit (`prepareKeys`,
`hybridSignature`, `HybridSigner`) treats a 1,312-byte public key as ML-DSA-44.

Test vector (same mnemonic, profile `pq`, index 0): ECDSA key as above; SHA-256 of the 1,312-byte
ML-DSA-44 public key `ac0882837d8d1a2f1b2fba51c5cb0c1403b1acbb64d951e1bd522ed6c936e599`.

The browser page (`docs/index.html`) restores ML-DSA-44 keys when the account's on-chain key is 43 felts
and signs with them; it has no ML-DSA-44 demo account (no ML-DSA-44 class is declared on Sepolia yet).
