# Key backup profile v0.2: Falcon-1024

Status: experimental, unaudited, testnet only (PF-14). Profiles v0 and v0.1
([key-backup-v0.md](key-backup-v0.md)) are unchanged; v0.2 only adds a Falcon-1024 key.

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

The browser page (`docs/index.html`) does not offer v0.2.
