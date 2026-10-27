// PF-04 on Sepolia: declare the Provably Fast verifier classes and collect the receipts of complete
// transactions with each verifier. TESTNET ONLY.
//
//   node pf04_sepolia.mjs declare HybridShakeVerifierPfCompact       # from the deployer
//   PQ_MATRIX_RUN=pf04-compact PQ_VERIFIER_CLASS=<compact class hash> \
//     node wallet_migrate_demo.mjs argent-0.5.0 braavos-1.2.0 argent-0.3.1
//   node pf04_sepolia.mjs declare VerifierSwitchGuard pf04-compact argent-0.5.0
//                                  # from that migrated account: a declare validated by the compact
//                                  # verifier (a small class, so the declare itself is cheap)
//   node pf04_sepolia.mjs receipts                                   # writes bench/pf04/sepolia.json
//
// Only the selected (compact) verifier is declared on Sepolia: a verifier class costs on the order
// of 100+ STRK to declare. The record verifier is measured locally (bench/pf04). A record run uses
// PQ_MATRIX_RUN=pf04-record and is collected the same way. Baseline receipts are the
// HybridShakeAccount-verifier runs in contracts/docs/wallet-coverage.md.
// sepolia.json holds transaction hashes and receipts only, never keys or words.
import { Account, RpcProvider, hash, json, num } from "starknet";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { HybridSigner, deriveAccountKeys, prepareKeys } from "./pq_account_kit.mjs";
import { KEYS, ROOTS, RPC, TARGET } from "./config.mjs";

const provider = new RpcProvider({ nodeUrl: RPC });
const STATE_FILE = `${KEYS}/pf04-sepolia-state.json`;
const OUT = resolve(TARGET, "../../../bench/pf04/sepolia.json");
const OZ_ACCOUNT_CLASS = "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";
const RUNS = { compact: "pf04-compact", record: "pf04-record" };
const PROFILES = { "argent-0.5.0": "argentx", "argent-0.3.1": "argentx", "braavos-1.2.0": "braavos" };
// Baseline (HybridShakeAccount verifier): contracts/docs/wallet-coverage.md, migratable class 0x4b067679….
const BASELINE = {
  "argent-0.5.0": { migration: "0x2bd473956e65ee2a017ddcfd4b5a03710fa329f1fdfa60e0de2c05f4dd91f77", hybridTransfer: "0x348a4cac1c1b0479057a18f021ac9a65e36f18ee6c5839644ef627fe77309d" },
  "braavos-1.2.0": { migration: "0x1a4972fc9e3315c62ebaec99a40de4248e86bbe15ebf5f3892bfc33b71e89f5", hybridTransfer: "0x1f214500c70833bf88fa6d03c33999a7b23dec0ac188d761c8018d3d078d5c2" },
  "argent-0.3.1": { migration: "0x6d4959b5a61b74af5290f718558bad4eabc1dc662bcd5af072425873c7132b4", hybridTransfer: "0x7a568054220fe93b40f335dde033bfc9fad008a2f1699f6e7c59ed7333ac91c" },
};
const state = existsSync(STATE_FILE) ? JSON.parse(readFileSync(STATE_FILE, "utf8")) : {};
const save = () => writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function retry(fn, tries = 6) {
  for (let i = 0; ; i++) {
    try { return await fn(); } catch (e) {
      if (i + 1 >= tries || !/cu limit|too fast|429|rate|ECONNRESET|fetch failed/i.test(e?.message || "")) throw e;
      await sleep(3000 * (i + 1));
    }
  }
}

function signerAccount(run, wallet) {
  if (!run) {
    const deployer = JSON.parse(readFileSync(`${KEYS}/deployer-ecdsa.json`, "utf8"));
    return new Account({ provider, address: readFileSync(`${KEYS}/deployer-address.txt`, "utf8").trim(), signer: deployer.privateKey });
  }
  const s = JSON.parse(readFileSync(`${KEYS}/wallet-matrix-state-${run}.json`, "utf8"))[wallet];
  if (s?.migration?.status !== "SUCCEEDED") throw new Error(`${run} ${wallet} is not migrated`);
  const words = readFileSync(`${KEYS}/wallet-${run}-${wallet}-mnemonic.txt`, "utf8").trim();
  const keys = prepareKeys(deriveAccountKeys(words, 0, PROFILES[wallet]), JSON.parse(readFileSync(ROOTS, "utf8")));
  return new Account({ provider, address: s.address, signer: new HybridSigner(keys) });
}

// The deployer is a plain OpenZeppelin account (signer/setup_keys.mjs); deploy it on first use.
async function ensureDeployed(acc) {
  try { await provider.getClassHashAt(acc.address); return; } catch { /* not deployed */ }
  const { publicKey } = JSON.parse(readFileSync(`${KEYS}/deployer-ecdsa.json`, "utf8"));
  console.log(`deploying deployer ${acc.address}...`);
  const r = await acc.deployAccount({ classHash: OZ_ACCOUNT_CLASS, constructorCalldata: [publicKey], addressSalt: publicKey, contractAddress: acc.address });
  await retry(() => provider.waitForTransaction(r.transaction_hash));
}

async function declare(name, run, wallet) {
  const sierra = json.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.contract_class.json`, "utf8"));
  const casm = json.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.compiled_contract_class.json`, "utf8"));
  const classHash = hash.computeContractClassHash(sierra);
  const acc = signerAccount(run, wallet);
  if (!run) await ensureDeployed(acc);
  console.log(`declaring ${name} ${classHash} from ${run ? `${run} ${wallet}` : "deployer"} ${acc.address}`);
  try {
    await provider.getClassByHash(classHash);
    console.log("already declared");
    return;
  } catch { /* not declared yet */ }
  // starknet.js estimates the fee (with its default margin), so the balance needed is the
  // estimate plus margin rather than a fixed worst-case bound.
  const d = await acc.declare({ contract: sierra, casm }, { tip: 0n });
  const rc = await retry(() => provider.waitForTransaction(d.transaction_hash));
  state.declares = { ...state.declares, [name]: { tx: d.transaction_hash, classHash, from: run ? `${run} ${wallet}` : "deployer", status: rc.execution_status } };
  save();
  console.log(`declare ${rc.execution_status}: ${d.transaction_hash}, l2 gas ${rc.execution_resources?.l2_gas}`);
}

async function receipt(tx) {
  const rc = await retry(() => provider.getTransactionReceipt(tx));
  const blk = await retry(() => provider.getBlockWithTxHashes(rc.block_number));
  await sleep(500);
  return {
    tx, status: rc.execution_status, block: rc.block_number, timestamp: blk.timestamp,
    l2_gas: Number(rc.execution_resources.l2_gas), l1_data_gas: Number(rc.execution_resources.l1_data_gas),
    l1_gas: Number(rc.execution_resources.l1_gas || 0), fee_fri: BigInt(rc.actual_fee.amount).toString(),
    l2_gas_price_fri: BigInt(blk.l2_gas_price.price_in_fri).toString(),
  };
}

async function receipts() {
  const out = { description: "PF-04 Sepolia receipts; see bench/pf04/README.md", generated_utc: new Date().toISOString(), runs: {} };
  out.runs.baseline = {};
  for (const [wallet, txs] of Object.entries(BASELINE)) {
    out.runs.baseline[wallet] = { migration: await receipt(txs.migration), hybridTransfer: await receipt(txs.hybridTransfer) };
  }
  for (const [variant, run] of Object.entries(RUNS)) {
    const file = `${KEYS}/wallet-matrix-state-${run}.json`;
    if (!existsSync(file)) continue;
    const runState = JSON.parse(readFileSync(file, "utf8"));
    out.runs[variant] = {};
    for (const wallet of Object.keys(PROFILES)) {
      const s = runState[wallet];
      if (!s?.migration) continue;
      out.runs[variant][wallet] = {
        verifierClass: s.before?.verifierClass,
        migration: await receipt(s.migration.tx),
        hybridTransfer: s.hybridTransfer ? await receipt(s.hybridTransfer.tx) : null,
        keysPreserved: s.after ? s.after.ecdsaKeyMatchesWords && s.after.falconKeyMatchesWords : null,
        balanceDropEqualsFee: s.after?.balanceDropEqualsFee ?? null,
        ecdsaOnlyTransfer: s.ecdsaOnly ?? null,
      };
    }
  }
  out.declares = {};
  for (const [name, d] of Object.entries(state.declares || {})) {
    out.declares[name] = { classHash: d.classHash, from: d.from, ...(await receipt(d.tx)) };
  }
  writeFileSync(OUT, JSON.stringify(out, null, 2) + "\n");
  console.log(`wrote ${OUT}`);
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd === "declare") await declare(...args);
else if (cmd === "receipts") await receipts();
else { console.error("usage: pf04_sepolia.mjs declare CLASS_NAME [RUN WALLET] | receipts"); process.exit(1); }
