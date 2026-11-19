# Dormant PQ key (ARCH-02)

Status: experimental, unaudited, testnet only. Built and tested in Cairo
(`contracts/src/dormant.cairo`, `contracts/src/tests_dormant.cairo`); not declared on any network,
no wallet-kit support yet. Issue: [#26](https://github.com/Ryun1/starknet-pq-account/issues/26).

## What it is

`HybridDormantAccount` validates with ECDSA alone (~31K per transaction, the target in #26; the
dormant path is not yet measured on devnet) and stores one felt: a Poseidon commitment to a PQ key
and the verifier class that will check it. When quantum attacks on ECDSA become credible, the owner
reveals the key with `activate`, and from then on the account requires a hybrid signature, as a
registered `HybridMigratableAccountV2` does. The storage is the same, so an active account can
`upgrade` to V2 for key rotation and scheme switches.

```
commitment = poseidon('starknet-pq-dormant-commit-v1', verifier_class_hash, setup_class_hash, pq_key...)
activation = poseidon('starknet-pq-dormant-activate-v1', chain_id, account, ecdsa_key, pq_key...)
```

The PQ key is derived from the same mnemonic as the ECDSA key (key backup v0.1), so the wallet only
needs the commitment at setup and re-derives the key at activation.

| State | Stored | `__validate__` accepts | `is_valid_signature` |
| --- | --- | --- | --- |
| Unregistered | neither | ECDSA, one self-call to `commit` | 0 |
| Dormant | commitment | ECDSA; self-calls only to `propose_commitment`, `activate` | ECDSA |
| Active | PQ key, verifier | hybrid | hybrid |

## Threat model

Attackers considered:
- **A**: can forge ECDSA signatures for this account (after Q-day, or a leaked key).
- **B**: holds neither key and can only send transactions from their own account.
- **L**: the owner has lost the PQ key, or the committed verifier is found broken.

### Who can change the commitment

ECDSA alone can `propose_commitment`. `apply_commitment` (anyone) accepts it after
`DORMANT_DELAY` = 7 days. `commit` works only once, on an unregistered account. A zero commitment is
refused everywhere, so ECDSA alone can neither remove the PQ key nor replace it faster than the
delay.

- **A** proposes their own key. The owner sees `CommitmentProposed` and activates before
  `ready_at`. Activation clears the proposal (the veto). If the owner does not notice within 7
  days, A takes over the emergency path. **Wallets must alert on `CommitmentProposed`.** Nothing
  here does that yet.
- **A** keeps re-proposing to restart the clock. This only delays their own proposal.
- **L**: the owner proposes a fresh commitment and waits 7 days. An immutable commitment was
  rejected because it leaves no fix for L.

### Activation trigger

Activation needs the owner's proof only. Not built: guardians (they belong to ARCH-03 / OZ-01) and
an on-chain signal that refuses ECDSA alone network-wide. No such register exists to read. If one
appears, it is one extra check in the dormant branch of `__validate__`.

Activation is one-way. Returning to dormant would re-open the ECDSA-only path, so the class has no
entry point for it.

### What ECDSA alone may do while dormant

Any call to another contract. No self-call except `propose_commitment` and `activate`, checked for
every call of a multicall in `__validate__`. This blocks `upgrade` and any selector the class does
not have. Without the block, **A** could upgrade the class or rotate the ECDSA key, and the owner's
hybrid activation proof (which uses the current ECDSA key) would stop verifying.

The cost of the block: a dormant account cannot upgrade its class before activating. Pre-Q-day, an
owner who wants another class has to activate first.

### Race window and the loss bound

**Until the owner activates, A can move everything ECDSA reaches: the whole balance and every
approval.** This design does not shorten the race. It only guarantees the owner can still take the
account back once they act. Spend caps and delayed large transfers (ARCH-03,
[#27](https://github.com/Ryun1/starknet-pq-account/issues/27)) are the mitigation.
`is_valid_signature` is ECDSA-only while dormant (dapps need it), so A can also forge off-chain
signatures (permits, SNIP-12 logins), as for any ECDSA account.

### Activation proof and its binding

`proof` is a hybrid signature by the current ECDSA key and the revealed PQ key over
`activation_hash`, checked by the committed verifier after the key is written. The commitment
binds the verifier and setup classes. If activation could choose them, **A** could activate with a
verifier that accepts anything. The setup class and the verifier run in the account's storage, so
activation re-checks the keys, verifier pointer and cleared commitment afterwards and reverts on
any change.

- **A** cannot produce the PQ half.
- Replay: the hash binds the chain id and the account address, so a proof for one account or
  network does not activate another with the same keys. Activation is one-shot (the state changes),
  so no nonce is needed.
- Front-running: anyone who copies the owner's activation submits the same activation, which helps
  the owner.

### Fee griefing

`activate` runs in execution, not `__validate__`, and anyone may call it. **B** calling it with a
bad proof pays their own fee and reverts their own transaction. The owner can also call it from the
account itself (an ECDSA-signed self-call). The proof is checked the same way there, and **A**
gains nothing from sending it. Nothing PQ runs in the dormant `__validate__`.

### Key type

Falcon-512, through the existing verifier classes and `HybridSigner`. Hash-based one-time keys
(WOTS+/LMS, PF-15 item 4) fit "used once" better, but there is no verifier for them yet. Because the
commitment names a verifier class, one can be added later without changing the account.

### Overlap with `recovery/`

None in code. The ZK seed proof in `recovery/` is the fallback for accounts that never committed.
This class is the cheap path for those that do.

## Supported routes

- **Fresh deployment**: `constructor(ecdsa_public_key, commitment)`.
- **OpenZeppelin-style accounts** (ECDSA key already in `Account_public_key`): one ECDSA-signed
  multicall `[upgrade(dormant class), commit(commitment)]`. Tested with the `LegacyOzLikeAccount`
  stand-in.
- **Not supported yet: Argent and Braavos.** Their key lives elsewhere, so `commit` would need the
  ECDSA key as an argument plus a proof of possession, or a wrong key would lock the account. For
  now, use V2 migration for those accounts.

## Not done

- Wallet kit: `dormantCommitment`, `activationCalls`, a pre-flight that simulates activation at
  commit time (checks the derived key opens the commitment, without an on-chain proof), and
  `inspectAccount` / `HybridSigner` support for the dormant state.
- A real Falcon activation fixture. The activation hash binds the account address, which changes
  with the class hash in Cairo tests. Tests use the mock scheme for success paths, and the real
  verifier for rejection.
- Devnet measurement of dormant `__validate__` against a plain ECDSA account, and of activation.
- Independent review. The security claims above have not been reviewed.
