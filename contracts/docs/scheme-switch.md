# Changing the post-quantum key or scheme: `HybridMigratableAccountV2`

Status: experimental, unaudited, testnet only. The class is built and tested locally
(`contracts/src/migratable_v2.cairo`, `tests_scheme.cairo`). It is not declared on Sepolia and is
not in `release/testnet-v1.json`. It has been tested with SHAKE-256 Falcon-512, Falcon-1024
(`HybridShakeVerifierFalcon1024`, PF-14, [`bench/pf14`](../../bench/pf14/README.md)) and a mock
scheme with a setup class (see [Tests](#tests)).

## Why a new account class

The verifier is a replaceable class, but `HybridMigratableAccount` itself fixes the PQ key at 29
felts in three places (`_register`, `_falcon_registered`, `rotate_falcon_public_key`). A
Falcon-1024 key (57 felts) or an ML-DSA-44 key (43) cannot be stored, and
`set_verifier_class_hash` only moves between verifiers that accept the same signature
([verifier-replacement.md](verifier-replacement.md)).

V2 is the same account without that length. It does not know the scheme: the verifier class
decides what a valid key and signature are, and every path that writes a key requires a proof,
checked through that verifier, that the owner can sign with it. It is needed once, not per scheme.

## What changed against `HybridMigratableAccount`

| | Earlier class | V2 |
| --- | --- | --- |
| Registered | key length is 29 | a key is stored |
| PQ key | `rotate_falcon_public_key(key, proof)`, 29 felts, same verifier | `set_pq_key(key, verifier, setup, proof)`, any length, any verifier |
| `migrate`, `MigrationData`, constructor | key, verifier | key, verifier, setup class |
| `set_verifier_class_hash`, `rotate_ecdsa_public_key`, `upgrade`, getters, bootstrap | | unchanged |

Storage names and types are the same, so an account that upgrades keeps its keys and verifier.
`falcon_public_key` is the PQ key's storage name whatever the scheme, because the declared
verifier classes read it by that name through the library call. `get_falcon_public_key` and
`is_falcon_registered` keep their names for the same reason: wallets and the guard call them.

## `set_pq_key`

```
account.set_pq_key(pq_public_key, verifier_class_hash, setup_class_hash, proof)
```

A self-call in a hybrid-signed transaction. It:

1. writes the new key, replacing the old one whatever their lengths, and the verifier pointer;
2. if `setup_class_hash` is not zero, library-calls its `setup_pq_key()`, for schemes that store
   work derived from the key (ML-DSA's expanded matrix);
3. requires `proof` to verify through the new verifier;
4. requires the classical key, its mirror, the PQ key and the verifier pointer to be what it
   wrote, since the verifier and the setup class ran in the account's storage.

`proof` is a hybrid signature by the current classical key and the **new** PQ key over
`rotation_hash(ecdsa_public_key, pq_public_key)`, the message key rotation already uses.

The transaction is validated by the **old** key and verifier in `__validate__`, and the proof by
the **new** ones in `__execute__`. So nothing has to verify under both schemes, and the proof
check does not count against the validation gas cap. If any step fails the call reverts and the
account keeps its old key and verifier. The fee is charged and the nonce advances.

## Routes

| From → to | Route |
| --- | --- |
| Same scheme, another verifier, same key | `set_verifier_class_hash` or the guarded `switchVerifier`, as before |
| Migrated account on an earlier class → another scheme | one hybrid-signed multicall `[upgrade(V2), set_pq_key(...)]` |
| Migrated account on an earlier class, same scheme | `upgrade(V2)` alone keeps the key and verifier |
| V2 account → another scheme, or a new PQ key | `set_pq_key` |
| Unmigrated Argent / Braavos / OpenZeppelin → any scheme | the existing migration flows with the V2 class and its `MigrationDataV2` |
| Directly deployed `HybridShakeAccount` / `HybridPoseidonAccount` | none, as before: no upgrade entry point |

Kit: `setPqKeyCalls(address, current, next, { verifierClass, setupClass, upgradeTo })` builds the
calls and the proof, and `sendSimulated(account, calls)` simulates them with validation before
sending (`signer/pq_account_kit.mjs`). `migrationCalls` takes `setupClass` when the target is V2.

## Limits

- **Trusted code.** The verifier and the setup class run in the account's storage and can read or
  write anything there. The state check sees the keys and the verifier pointer, not every slot.
  The kit refuses a verifier or setup class that is not in its allowed list; allow only reviewed,
  pinned class hashes.
- **One signature.** The proof shows that this key, verifier and setup accept one signature. It
  does not show the verifier is correct on other inputs; that is what a differential suite is for.
- **The proof is not an authorization.** It prevents lock-out. Authority comes from the
  transaction's own hybrid signature, so an ECDSA-only transaction cannot call `set_pq_key`.
- **Downgrades are possible.** An account can move to a weaker scheme by its own hybrid signature.
- **`upgrade` is not checked**, as on the earlier class: the class it installs is trusted.
- **Setup must fit one transaction.** A scheme whose setup exceeds the execution gas cap (ML-DSA-87
  at about 3.1B, external figure) cannot use `set_pq_key` as it is.
- `rotate_falcon_public_key` no longer exists on V2. `rotationCalls` in the kit targets the
  earlier class; on V2 use `setPqKeyCalls` for the PQ key.

## Tests

`contracts/src/tests_scheme.cairo`, 26 cases, run as transactions (`__validate__`, then
`__execute__`). Each failing case asserts its revert reason and that the keys, the verifier
pointer and signature checks are as before.

| Case | Result |
| --- | --- |
| earlier-class account, `upgrade(V2)` alone, then a transaction | keys and verifier kept, validates |
| earlier-class account, `[upgrade(V2), set_pq_key]` to the mock scheme (3-felt key, setup class) | installed; old signature rejected in a check and in a transaction |
| back to SHAKE-256 Falcon-512 with another key, signed with the mock scheme | installed; key grows from 3 to 29 felts |
| `set_pq_key` with the same verifier and a new Falcon key | rotated |
| proof by the current key; a key nobody holds; a 3-felt key under the Falcon verifier; the Poseidon verifier for a SHAKE-256 proof; a scheme that needs setup without it | reverts: `Migratable: invalid key proof` |
| empty key; zero verifier | reverts: `Migratable: empty pq key`; `Migratable: invalid verifier` |
| undeclared verifier; setup class without `setup_pq_key` | reverts: `CLASS_HASH_NOT_DECLARED`; `ENTRYPOINT_NOT_FOUND` |
| setup class that rewrites the mirrored classical key | reverts: `Migratable: state changed` |
| ECDSA-only transaction calling `set_pq_key` | rejected in `__validate__` |
| outsider; unmigrated account | `Migratable: only self`; `Migratable: not registered` |
| raw `set_verifier_class_hash` to another scheme | reverts: `Migratable: verifier rejects` |
| OpenZeppelin, Argent 0.4+ and Argent 0.3.x migration straight to V2; to the mock scheme with setup | migrated |
| bootstrap; migrate twice; fresh deployment; `rotate_ecdsa_public_key` | as on the earlier class |
| Falcon-512 → Falcon-1024 → Falcon-512 with `set_pq_key` (57 felts, then 29); a v1 account moved to Falcon-1024 by `[upgrade, set_pq_key]`; an Argent account migrated straight to Falcon-1024 | switched; each scheme's signatures pass only while it is installed |
| a 29-felt key under the Falcon-1024 verifier; a Falcon-1024 key under a Falcon-512 verifier | reverts: `Migratable: invalid key proof` |
| raw `set_verifier_class_hash` to the Falcon-1024 verifier | reverts: `Migratable: verifier rejects` |

Removing the proof check from `set_pq_key` fails six of these, removing its state check fails the
key-rewriting case, and not clearing the old key before writing the new one fails three.

The mock scheme has no cryptography: its signature is `[hash + key[0]]`. It tests the account (a
key of another length, a setup class, a proof checked by the new verifier), not a verifier.
Falcon-1024 (issue #22) is the first real second scheme; its fixture is
`tests_falcon1024_fixture.cairo` (`signer/falcon1024_fixture.mjs`). ML-DSA-44 is separate work (#21).
`set_pq_key` from Falcon-512 to Falcon-1024 costs 78.8M L2 gas in `__execute__`, and a migration
straight to Falcon-1024 84.3M ([`bench/pf14`](../../bench/pf14/README.md)).

`signer/scheme_switch_check.mjs` checks offline that the kit's `set_pq_key` and V2 `migrate`
calldata match the compiled ABI, and that the proof signs the hash the Cairo test verifies.

## Size

Scarb 2.18.0, audited libfunc list: 9,748 CASM felts, 4,564 Sierra felts, 593,775,360 declare L2
gas by the PF-04 formula (10.2% of the 5.8e9 block cap). The earlier class is 8,866 and 4,124.
Transaction gas has not been measured.
