# Wallet coverage

Which existing Starknet accounts this kit can move in place, tested three ways: one real account
per wallet class on Sepolia, a read-only classification of recent mainnet senders, and the same
classification applied to every account that delegates BTC in Starknet staking.

Experimental, unaudited, testnet only. Nothing here touches mainnet funds.

## Sepolia: one real account per wallet class seen on mainnet

`signer/wallet_migrate_demo.mjs` creates fresh words for each wallet, derives the classical key
with that wallet's derivation (`argentx` for Argent, `braavos` for Braavos, `pq` for
OpenZeppelin and for the Xverse and OKX classes, whose wallets do not publish their derivation),
deploys a real account of that class, and migrates it with
`pq_account_kit.mjs` only (`inspectAccount`, then `migrationCalls`). Migratable class:
`0x5faf94f20ce4b58b22805b4199b889adb302904301890d3d723bea7b62a9f72` (declared 2026-11-16; adds
the state check on verifier switches to the 2026-11-02 class, migration paths unchanged). Runs on
earlier classes (`0x7efafbfb…`, `0x4b067679…`, `0x143276dc…`) are in the git history of this file.
Run with `PQ_MATRIX_RUN=v4`; the account is topped up to the migration's fee bound at the day's
L2 gas price before it migrates.

| Wallet class | Sierra | Migration transaction | L2 gas | Hybrid transfer |
| --- | --- | --- | --- | --- |
| Argent 0.3.0 | 1.2.0 | `upgrade` → `execute_after_upgrade` [0x3cce0e29…](https://sepolia.voyager.online/tx/0x3cce0e29839a1e454d509d465bd0d6f9d47a17b5c1a39ca2e8696e6d0086f6) | 153.5M | [0x19025517…](https://sepolia.voyager.online/tx/0x19025517dba7c95f9c7f621179ee3120b643a8a155d4dbc969ce70ddf62033) |
| Argent 0.3.1 | 1.4.0 | `upgrade` → `execute_after_upgrade` [0x6fd63896…](https://sepolia.voyager.online/tx/0x6fd63896588dd1cc6c58087cc84e36be03cbe5782abc99c9cb3e57527a47a34) | 138.0M | [0x38d6ad11…](https://sepolia.voyager.online/tx/0x38d6ad11abc78f441535921ed4a90872c6b1a2bbb5bb2a47663ca4de42e9877) |
| Argent 0.4.0 | 1.5.0 | `upgrade` → `perform_upgrade` [0x28e3c69d…](https://sepolia.voyager.online/tx/0x28e3c69d35fc917f2637e0e2a7d6a3477415883a834d29945a604aa55e483c3) | 153.5M | [0x1e24afcb…](https://sepolia.voyager.online/tx/0x1e24afcb7c32eb19ea1b244f23568e4bb8a6f5ed7e433ccd532b91f1b373e37) |
| Argent 0.5.0 | 1.7.0 | `upgrade` → `perform_upgrade` [0x4ae01ad7…](https://sepolia.voyager.online/tx/0x4ae01ad73c9e52fcfe737d9ac986ac040b63f6bc7023cf3606cd61118968fbe) | 74.7M | [0x494ea786…](https://sepolia.voyager.online/tx/0x494ea7867e30f71ed5277d4f354abac8b8c367005fcd769b24286f88fefe01b) |
| Braavos 1.0.0 | 1.4.0 | `[upgrade, migrate]` [0x4dcc2f43…](https://sepolia.voyager.online/tx/0x4dcc2f436a9f8da23fc7f9f2701e096d1639a16b77f70133b03651fac35b6c9) | 138.0M | [0x46a30f82…](https://sepolia.voyager.online/tx/0x46a30f822e555d696d8f375feb0111f71c6cdf02eb1aa4c0f2b39dcdab5d952) |
| Braavos 1.1.0 | 1.6.0 | `[upgrade, migrate]` [0x69045b61…](https://sepolia.voyager.online/tx/0x69045b610854d3abc81309b70a57bdd822818e83123ee3a3c8c12b64b893744) | 153.5M | [0x436ed720…](https://sepolia.voyager.online/tx/0x436ed72019060db4a35dce4296b35a06d08eae3fd3a942e21c93b2ef0d2966d) |
| Braavos 1.2.0 | 1.7.0 | `[upgrade, migrate]` [0x73635a00…](https://sepolia.voyager.online/tx/0x73635a00e34649854f67081c3e7136b41748081de4abe027ce571682946bc17) | 70.1M | [0x2a4194f8…](https://sepolia.voyager.online/tx/0x2a4194f88f7a85fcffffd89d6cc1806e307be6f3cd211a0b48932630b92e08f) |
| OpenZeppelin `0x05b4b537…` | 1.6.0 | `[upgrade, migrate]` [0xc4bce24b…](https://sepolia.voyager.online/tx/0xc4bce24b97b6e2879840b429016ce50b1ebdd3ceeeccc7dd1c03ca2fffddb6) | 137.6M | [0x3df6441d…](https://sepolia.voyager.online/tx/0x3df6441dabe824e2b1188302a68f656314a4b608d8ddc0ef7704e325777add6) |
| OpenZeppelin `0xe2eb8f56…` | 1.5.0 | `[upgrade, migrate]` [0xf12464af…](https://sepolia.voyager.online/tx/0xf12464af1e2139192a58c61bf0c4832dd745b9e664f9bbdb862c92dc1c3071) | 137.6M | [0x2d465c68…](https://sepolia.voyager.online/tx/0x2d465c68d2292957c163a5f4e96e087b958aaab375704cc33a07dd9f47247) |
| Xverse (`ArgentAccountXverse`, Argent 0.4.0 base) | 1.5.0 | `upgrade` → `perform_upgrade` [0x5b557433…](https://sepolia.voyager.online/tx/0x5b5574332113fc27b8676341b43c429ffd394b638d9d071d75fb9504c882007) | 138.0M | [0x751438c7…](https://sepolia.voyager.online/tx/0x751438c73a5c163d97a4b176b8d8c19007ea3f7d7c327e2ce830197995a9588) |
| OKX (`OkxAccount`, Argent 0.3.0 base) | 1.2.0 | `upgrade` → `execute_after_upgrade` [0x46dbc7a2…](https://sepolia.voyager.online/tx/0x46dbc7a2532605ecc4a50b2e31f4269dcfd1383e8589135fd1b67b31e8ff2d1) | 153.5M | [0x5a0ceb12…](https://sepolia.voyager.online/tx/0x5a0ceb12939016ac01c0595ec15be3abae5311fa007c22aa204fea2edfb170f) |

For all eleven accounts: the classical and Falcon keys stored after migration equal the keys derived
from its words, the balance dropped by exactly the migration fee, the hybrid-signed transfer
succeeded, and an ECDSA-only transfer was rejected in `__validate__`. Sierra versions are read
from the first three felts of each class's `sierra_program`.

These runs use the baseline `HybridShakeAccount` verifier. Argent 0.5.0, Argent 0.3.1 and Braavos
1.2.0, one per callback path, were also migrated with the small Provably Fast verifier, with the
same checks ([`bench/pf04`](../../bench/pf04/README.md#sepolia-receipts),
[`bench/pf06`](../../bench/pf06/README.md)).

### ML-DSA-44 (release `testnet-v2`)

`signer/pf13_sepolia.mjs` ran the same checks with ML-DSA-44 on 2026-11-26, on
`HybridMigratableAccountV2` (`0x7c7c9de0…b154`, [`release/testnet-v2.json`](../../release/testnet-v2.json)):
Argent 0.5.0 (`perform_upgrade`) and Braavos 1.2.0 (`[upgrade, migrate]`), plus an account moved
from Falcon-512. ML-DSA-44 keys follow
backup profile [v0.2](key-backup-v0.2.md).

| Start | Move transaction | L2 gas | L1 data gas | Hybrid transfer |
| --- | --- | --- | --- | --- |
| Argent 0.5.0 | `upgrade` → `perform_upgrade`, straight to ML-DSA-44 [0x5b1aeaa6…](https://sepolia.voyager.online/tx/0x5b1aeaa665ba33cbe6ecc672271b4e6d38d9ee088d57e42883536c517c82f3b) | 459.1M | 44,896 | [0x78081446…](https://sepolia.voyager.online/tx/0x7808144689c22d915638656ac0cc94bcd79048fa1495cb75803a5dca557f32f) |
| Braavos 1.2.0 | `[upgrade, migrate]`, straight to ML-DSA-44 [0x2d9802f3…](https://sepolia.voyager.online/tx/0x2d9802f35856f6b1f37d1c6d8d92677d83c1cec4460ffd075d54f0cf1ad15fc) | 458.7M | 44,896 | [0x22e7bf8c…](https://sepolia.voyager.online/tx/0x22e7bf8c468de274f1526d2efb611f44716c59b0d19286abcdcc9d0cda5a82f) |
| Argent 0.5.0 already on Falcon-512 (`testnet-v1`) | `[upgrade V2, set_pq_key]` [0x9d3675d7…](https://sepolia.voyager.online/tx/0x9d3675d79dba977285e9327c1e79f581fc68d9f497ac564bb251fe327d0bf0) | 479.4M | 43,712 | [0x26065dfb…](https://sepolia.voyager.online/tx/0x26065dfbf1580f339df0e2f3059d7c74f432a549c9f68e01413137e8326bed8) |

For all three: the stored ECDSA and ML-DSA-44 keys equal the keys from the words, the balance
dropped by exactly the move's fee, the hybrid transfer (about 44.7M L2 gas) succeeded, and an
ECDSA-only transfer was rejected in `__validate__`. The move writes the key and a 419-slot cache,
so a wallet must bound L1 data gas at about 45K or more; a 5,000 bound reverts after running
([`bench/pf13`](../../bench/pf13/README.md#sepolia-receipts-plan-step-10-2026-11-26)). The other
nine wallet classes above were not re-run with ML-DSA-44; Argent 0.3.x and OKX use the third
callback path, `execute_after_upgrade`, which no ML-DSA-44 move has exercised.

### Gas

Migrations started from classes compiled with Sierra 1.7.0 (Argent 0.5.0, Braavos 1.2.0) used
70 to 75M L2 gas. Those started from older classes used 138 to 153M. Our class is Sierra 1.8.0
in both cases, so the difference most likely comes from how Starknet meters execution that
starts in a pre-1.7.0 class; we have not confirmed the exact rule. At the mainnet prices in the
README (11.34 x 10^9 fri per L2 gas, STRK at $0.0775), that is about 0.8 STRK ($0.06) or 1.74
STRK ($0.13), once per account.

## Mainnet: which recent senders could migrate today

`signer/mainnet_survey.mjs` walks back from the latest mainnet block, collects unique INVOKE
senders until it has 400, and classifies each with `inspectAccount`: the class ABI decides the
wallet family (cached per class), then per-account reads check Argent owners and guardians and
Braavos signers and multisig. Read-only; only the aggregate is published
([`signer/survey/mainnet-summary-2026-10-19.json`](../../signer/survey/mainnet-summary-2026-10-19.json)).

Window: blocks 16,587,925 to 16,589,622 (about 0.8 hours on 2026-10-19), 4,839 INVOKE
transactions, 400 unique senders.

- 362 of 400 senders (90.5%) use a class this kit migrates; they sent 93.2% of the INVOKE
  transactions in the window. 3 of them have an Argent guardian, so the migration needs the
  guardian's co-signature.
- 353 of 400 (88.3%) are on the eleven classes migrated on Sepolia above. The other 9 are on
  three further OpenZeppelin-style classes, classified by ABI only.
- Not covered (38): 23 accounts with no self-upgrade entry point, 9 Cairo 0 accounts, 4 Braavos
  accounts with a hardware or passkey signer (migration would drop it), 2 others.

By class: Argent 0.4.0 195 (including 1 Xverse), OpenZeppelin-style 94, Argent 0.3.0 41
(including 2 OKX), Braavos 1.2.0 20, Argent 0.3.1 8, Braavos 1.0.0 5, Argent 0.5.0 2, Braavos
1.1.0 1, other 34.

Limits of this sample: under one hour, counted per sender, so it leans toward frequent senders
such as bots and market makers. It shows which account classes are in active use, not how much
value they hold; the BTC staking measurement below weights by value.

Second sample, same method
([`signer/survey/mainnet-summary-2026-11-16.json`](../../signer/survey/mainnet-summary-2026-11-16.json)):
blocks 18,060,385 to 18,062,339 (about 0.9 hours on 2026-11-16), 6,980 INVOKE transactions, 400
unique senders.

- 350 of 400 senders (87.5%) use a class this kit migrates; they sent 81.7% of the INVOKE
  transactions in the window. 4 of them have an Argent guardian.
- 344 of 400 (86.0%) are on the eleven classes migrated on Sepolia.
- Not covered (50): 22 accounts with no self-upgrade entry point, 17 Cairo 0 accounts, 3 Braavos
  accounts with a hardware or passkey signer, 8 others.

The two samples differ by three points; read them as "close to nine in ten senders", not as a
precise share.

## Mainnet: BTC staked on Starknet

`signer/btc_staking_coverage.mjs` lists every BTC delegation pool of the staking contract
(`NewDelegationPool` events for WBTC, tBTC, SolvBTC, LBTC and strkBTC), every member of those
pools (`NewPoolMember` events), each member's current delegated amount
(`get_pool_member_info_v1`), and classifies each delegating account with `inspectAccount`.
Read-only. On a public RPC node the pool scan from genesis can stall, so
`signer/btc_pools_update.mjs` extends a cached pool list from its last block instead.

On 2026-11-16
([`signer/survey/btc-staking-coverage-2026-11-16.json`](../../signer/survey/btc-staking-coverage-2026-11-16.json)):
485 BTC pools, 885 delegating accounts, 686.2 BTC delegated (SolvBTC 476.2, WBTC 172.2,
strkBTC 32.1, tBTC 5.3, LBTC 0.3).

- 631.1 BTC (92.0%) sits in 786 accounts this kit migrates today; 613.3 BTC of it in Argent
  0.4.0 accounts.
- The ten largest delegating accounts hold 501.5 BTC (73.1%); all ten are Argent 0.4.0 accounts
  that migrate with one `upgrade` call. Of the 834 accounts delegating under 1 BTC, 757 (91%)
  can migrate.
- Not covered: 42.2 BTC in accounts of other classes (likely contracts rather than personal
  wallets; unconfirmed), 11.9 BTC in Braavos accounts with a hardware or passkey signer,
  0.9 BTC in an Argent-based class under another name.

Earlier measurement, same method, on 2026-10-19
([`signer/survey/btc-staking-coverage-2026-10-19.json`](../../signer/survey/btc-staking-coverage-2026-10-19.json)):
484 BTC pools, 882 delegating accounts, 621.3 BTC delegated (SolvBTC 409.8, WBTC 174.8,
strkBTC 30.4, tBTC 5.3, LBTC 1.1).

- 563.6 BTC (90.7%) sits in 788 accounts this kit migrates today; 545.9 BTC of it in Argent
  0.4.0 accounts.
- The ten largest delegating accounts hold 435.1 BTC (70.0%); all ten are Argent accounts that
  migrate with one `upgrade` call. Of the 832 accounts delegating under 1 BTC, 759 (91%) can
  migrate.
- Not covered: 44.9 BTC in accounts of other classes (likely contracts rather than personal
  wallets; unconfirmed), 12.1 BTC in Braavos accounts with a hardware or passkey signer,
  0.8 BTC in an Argent-based class under another name.
