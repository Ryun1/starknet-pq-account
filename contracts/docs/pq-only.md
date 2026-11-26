# PQ-only mode: Falcon-only validation after migration (ARCH-01)

Status: experimental, unaudited, testnet only. Built and tested locally. The two Falcon-only
verifier classes are not declared on Sepolia and not in `release/testnet-v1.json`.
**Not recommended until a Falcon verifier has had an independent review (PF-08).**

## What it is

A migrated `HybridMigratableAccountV2` normally checks ECDSA **and** Falcon on every
transaction. PQ-only drops the ECDSA check: a transaction signature is the Falcon signature alone.

No account change. It is a verifier class, installed with V2's existing `set_pq_key`
([scheme-switch.md](scheme-switch.md)):

| Class (`contracts/src/hybrid.cairo`) | Checks | Signature |
| --- | --- | --- |
| `FalconOnlyVerifierPfSmall` | Falcon-512 SHAKE-256 (the `HybridShakeVerifierPfSmall` verifier) | 60 felts |
| `FalconOnlyVerifierFalcon1024` | Falcon-1024 (the `HybridShakeVerifierFalcon1024` verifier) | 116 felts |

The mode is the verifier pointer: an account is PQ-only while it points at one of these classes.
The ECDSA key stays in storage, unread, and `get_ecdsa_public_key` still returns it.

## Switching

**Hybrid → PQ-only.** One hybrid-signed transaction:

```
[ account.set_pq_key(pq_key, FalconOnlyVerifier…, 0, proof) ]
```

`proof` is a Falcon-only signature over `rotation_hash(ecdsa_key, pq_key)`, checked by the new
verifier after the write. Keep the same PQ key or switch to a new one (or to Falcon-1024) in the
same call. An account on the earlier class prepends `upgrade(V2)`.

Since the transaction is hybrid-signed, an ECDSA forger can't do it alone, and nor can a
Falcon forger.

**PQ-only → hybrid.** One Falcon-signed transaction, with a **new** ECDSA key:

```
[ account.rotate_ecdsa_public_key(new_ecdsa, falcon_proof),
  account.set_pq_key(pq_key, hybrid_verifier, 0, hybrid_proof) ]
```

Both proofs sign `rotation_hash(new_ecdsa, pq_key)`. The first is Falcon-only, checked by the
PQ-only verifier still installed. The second is hybrid by the new ECDSA key and the PQ key,
checked by the hybrid verifier. So it proves the new ECDSA key, as `migrate` does. A wrong proof
reverts the whole transaction and the account stays PQ-only.

**Why a new ECDSA key.** While the account is PQ-only, nothing exercises or protects the old ECDSA
key. By the time anyone switches back, that key may be exposed. The contract does not enforce a new
key (it would accept the old one with a valid proof). The kit does: `hybridModeCalls` refuses the
current ECDSA key. That was a deliberate choice, to keep the account class unchanged (issue #25: "no
new storage and no new entry point").

The raw `set_verifier_class_hash` cannot switch modes. It checks the transaction's own signature
through the new class, and a hybrid signature never passes a Falcon-only class.

## Threat model

| Attacker can | Hybrid | PQ-only |
| --- | --- | --- |
| forge ECDSA (quantum, leaked key) | nothing | nothing |
| forge Falcon (scheme break, verifier bug, leaked Falcon key) | nothing, ECDSA still required | **everything** |
| forge both | everything | everything |

**What PQ-only gains.** Operations, not security:
- one key to back up and sign with, and room for hardware signers that hold only a PQ key;
- no dependency on an ECDSA implementation in the signing path;
- 2 fewer felts of calldata per transaction, and a cheaper `__validate__` (see [Gas](#gas)).

**What it loses.** Defence in depth against Falcon. Under hybrid AND, a broken Falcon verifier,
a forgeable Falcon signature or a leaked Falcon key gains an attacker nothing without the ECDSA key
too. Under PQ-only it gains them the account. The Provably Fast verifiers are unaudited, and
the program has already had breaks (ML-DSA-87's `c_tilde`, [`bench/pf14/ml-dsa-87.md`](../../bench/pf14/ml-dsa-87.md)).

**When to recommend it.** Only when all of these hold:
1. the Falcon verifier class in use has had an independent review (PF-08), and its findings are resolved;
2. ECDSA is broken or near-broken, or the operational case is concrete (a PQ-only hardware
   signer, or an ECDSA library you need to remove);
3. the owner accepts that a Falcon break means total loss.

Until then: stay hybrid. A broken ECDSA key gains an attacker nothing under hybrid anyway.

**Off-chain signatures.** `is_valid_signature` follows the mode. In PQ-only it accepts Falcon
alone, so a dapp that checks SNIP-12 signatures through the account sees Falcon-only.

## Wallet kit (`signer/pq_account_kit.mjs`)

| Function | What |
| --- | --- |
| `PQ_ONLY_VERIFIERS` | the two class hashes (Scarb 2.18.0), kept equal to the build by `pq_only_check.mjs` |
| `pqOnlyCalls(address, keys, { verifierClass, upgradeTo, acceptUnreviewedVerifier })` | hybrid → PQ-only. Throws unless `acceptUnreviewedVerifier: true` |
| `hybridModeCalls(address, current, next, { verifierClass })` | PQ-only → hybrid. Throws if `next` keeps the current ECDSA key |
| `accountMode(provider, address)` | `"pq-only"` if the verifier is in `PQ_ONLY_VERIFIERS`, else `"hybrid"` |
| `new HybridSigner(keys, { pqOnly: true })` | signs Falcon alone |
| `falconSignature(hash, keys)` | the Falcon half of `hybridSignature` |

Send with `sendSimulated(account, calls)`, signing with the CURRENT mode's signer.

## Tests

`contracts/src/tests_pq_only.cairo`, 14 cases, run as transactions (`__validate__`, then
`__execute__`). A failing case checks its revert reason and that the keys and verifier are
unchanged.

| Case | Result |
| --- | --- |
| hybrid V2 account → PQ-only, key kept | Falcon-only passes; hybrid and ECDSA-only refused, in `is_valid_signature` and in a transaction; ECDSA key kept |
| earlier-class account, `[upgrade(V2), set_pq_key]` | same |
| ECDSA-only, or Falcon-only, transaction entering PQ-only | rejected in `__validate__` |
| proof by another Falcon key | reverts: `Migratable: invalid key proof` |
| right Falcon proof with ECDSA felts in front | reverts: `Migratable: invalid key proof` |
| raw `set_verifier_class_hash` to the PQ-only class | reverts: `Migratable: verifier rejects` |
| PQ-only → hybrid with a new ECDSA key | new hybrid pair passes; Falcon-only and the old ECDSA key refused |
| PQ-only → hybrid, `set_pq_key` proof by the old ECDSA key | reverts: `Migratable: invalid key proof`; still PQ-only, old key |
| hybrid-signed transaction leaving PQ-only | rejected in `__validate__` |
| outsider calling `set_pq_key` | `Migratable: only self` |
| Falcon-1024 PQ-only | Falcon-1024 alone passes; its hybrid form and Falcon-512 refused |
| a Falcon-512 key under the Falcon-1024 PQ-only class | reverts: `Migratable: invalid key proof` |

If the PQ-only verifier accepts any non-empty signature, 9 of the 14 fail.

`signer/pq_only_check.mjs` (offline) checks the kit's calls against the compiled V2 ABI, its
proofs against the hashes the Cairo tests verify, its two gates, the signer's modes, and that
`PQ_ONLY_VERIFIERS` are the built classes. `signer/pq_only_fixture.mjs` writes
`tests_pq_only_fixture.cairo`.

## Gas

`bench/arch01/run.sh` (snforge 0.59.0, Scarb 2.18.0, USC 2.10.2, L2 gas, each figure is the measured
test minus its `setup_` twin, as in `bench/pf14/gas`). It covers one fixture signature per
scheme on `HybridMigratableAccountV2`:

| Path | Hybrid | PQ-only | Saving |
| --- | ---: | ---: | ---: |
| `__validate__`, Falcon-512 (PfSmall, key read once) | 27,173,773 | 27,110,998 | 62,775 (0.23%) |
| `__validate__`, Falcon-1024 | 52,163,837 | 52,100,462 | 63,375 (0.12%) |
| `set_pq_key` hybrid → PQ-only, Falcon-512, same key (`__execute__`) | | 37,120,734 | |

Re-run on 2026-11-26 with scarb 2.22.0, snforge 0.64.1 and USC 2.11.0-rc.1: Falcon-512 27,310,543 /
27,241,768 (saving 68,775), Falcon-1024 52,527,737 / 52,458,362 (69,375).

The saving is the STARK ECDSA check, about 63–69K L2 gas depending on the compiler, plus 2 calldata felts. That is
negligible next to Falcon, so gas is no reason to switch. Devnet and Sepolia transactions have not
been measured.

## Limits

- **Not reviewed.** Neither verifier class has been reviewed, and PQ-only removes the check that
  would catch a bug in them. The kit's flag is a speed bump, not a review.
- **No on-chain new-key rule.** See above. A wallet that skips the kit can return to hybrid with
  the old ECDSA key.
- **Trusted code**, as for any verifier ([scheme-switch.md](scheme-switch.md#limits)): the class
  runs in the account's storage. Allow only reviewed, pinned hashes.
- **Not declared.** Each class is slightly smaller than its hybrid counterpart (no ECDSA), so
  each declare fits wherever the hybrid one does. CASM / Sierra felts at Scarb 2.18.0:
  `FalconOnlyVerifierPfSmall` 63,262 / 68,177 (hybrid `PfSmall` 64,163 / 68,569), and
  `FalconOnlyVerifierFalcon1024` 59,122 / 48,204 (hybrid 59,762 / 48,437; its declare cost is 4.43e9 L2
  gas, 76% of a block).
- `HybridShakeAccount` / `HybridPoseidonAccount` deployed directly have no upgrade path, and the
  earlier migratable class must `upgrade` to V2 first.

EXPERIMENTAL AND UNAUDITED: the security claims here need independent review before any reliance.
