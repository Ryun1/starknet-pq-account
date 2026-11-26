// PF-13 step 10 on Sepolia: declare HybridMigratableAccountV2, HybridMlDsa44Verifier and
// MlDsa44KeySetup, then move real accounts to ML-DSA-44 and collect the receipts. TESTNET ONLY.
//
//   node pf13_sepolia.mjs --plan     # class hashes, balance, what is done; sends nothing
//   node pf13_sepolia.mjs declare    # the three classes, from the deployer (PF13_MAX_FEE_STRK per declare, default 300)
//   node pf13_sepolia.mjs run        # the accounts below; idempotent, resumes from .keys/pf13-sepolia-state.json
//   node pf13_sepolia.mjs receipts   # writes bench/pf13/sepolia.json
//
// Accounts, each from fresh words (keys from the words, backup profile v0.2 for ML-DSA-44):
//   argent-0.5.0, braavos-1.2.0: migrate straight to ML-DSA-44 (migrationCalls, V2, with the setup)
//   falcon-512: an Argent 0.5.0 account migrated to the testnet-v1 class with Falcon-512
//     (shake-pf-small-v1), then moved with one hybrid-signed [upgrade V2, set_pq_key ML-DSA-44]
// Then for each: stored keys equal the words' keys, a hybrid (ECDSA + ML-DSA-44) transfer succeeds,
// an ECDSA-only transfer is rejected. sepolia.json holds hashes and receipts, never keys or words.
import { Account, CallData, RpcProvider, Signer, cairo, config, constants, ec, hash, json, num } from "starknet";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { generateMnemonic } from "@scure/bip39";
import { wordlist } from "@scure/bip39/wordlists/english";
import { HybridSigner, KNOWN_VERIFIERS, deriveAccountKeys, inspectAccount, migrationCalls, prepareKeys, setPqKeyCalls } from "./pq_account_kit.mjs";
import { KEYS, ROOTS, RPC, TARGET } from "./config.mjs";
import { MIGRATABLE_CLASS, verifierClass } from "./verifiers.mjs";

const provider = new RpcProvider({ nodeUrl: RPC });
const STATE_FILE = `${KEYS}/pf13-sepolia-state.json`;
const OUT = resolve(import.meta.dirname, "../bench/pf13/sepolia.json");
const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const BRAAVOS_BASE = "0x03d16c7a9a60b0593bd202f660a28c5d76e0403601d9ccc7e4fa253b6a70c201";
const VOYAGER = "https://sepolia.voyager.online";
const CLASSES = ["HybridMigratableAccountV2", "MlDsa44KeySetup", "HybridMlDsa44Verifier"];
const artifact = (name, kind) => json.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.${kind}.json`, "utf8"));
const H = Object.fromEntries(CLASSES.map((c) => [c, num.toHex(hash.computeContractClassHash(artifact(c, "contract_class")))]));
const V2 = H.HybridMigratableAccountV2, VERIFIER = H.HybridMlDsa44Verifier, SETUP = H.MlDsa44KeySetup;
const MLDSA_ALLOWED = { [VERIFIER]: "HybridMlDsa44Verifier (PF-13)", [SETUP]: "MlDsa44KeySetup (PF-13)" };
const FALCON_VERIFIER = verifierClass("shake-pf-small-v1");
// set_pq_key / migrate to ML-DSA-44 measured 414M / 420M L2 gas locally (bench/pf13/gas).
const MOVE_L2_MAX = 800000000n;
// Writing the ML-DSA-44 key and its 419-slot cache: about 45K L1 data gas on Sepolia (2026-11-26).
const MOVE_DATA_MAX = 80000n;
const V1_MIGRATION_L2_MAX = 250000000n;
const TRANSFER_L2_MAX = 120000000n;
const ACCOUNTS = {
  "argent-0.5.0": { profile: "argentx", cls: "0x073414441639dcd11d1846f287650a00c60c416b9d3ba45d31c651672125b2c2", ctor: (pk) => [0, pk, 1] },
  "braavos-1.2.0": { profile: "braavos", impl: "0x3957f9f5a1cbfe918cedc2015c85200ca51a5f7506ecb6de98a5207b759bf8a" },
  "falcon-512": { profile: "argentx", cls: "0x073414441639dcd11d1846f287650a00c60c416b9d3ba45d31c651672125b2c2", ctor: (pk) => [0, pk, 1], viaFalcon: true },
};

const state = existsSync(STATE_FILE) ? JSON.parse(readFileSync(STATE_FILE, "utf8")) : {};
const save = () => writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(...a);
const errTail = (e) => { const m = e?.message || String(e); return m.slice(Math.max(0, m.length - 300)); };
let TIP = 0n;

async function retry(fn, tries = 10) {
  for (let i = 0; ; i++) {
    try { return await fn(); } catch (e) {
      if (i + 1 >= tries || !/cu limit|too fast|429|rate|ECONNRESET|fetch failed/i.test(e?.message || "")) throw e;
      await sleep(3000 * (i + 1));
    }
  }
}

class EcdsaOnlySigner extends Signer {
  constructor(pk) { super(pk); this.pk = pk; }
  async signRaw(msgHash) { const e = ec.starkCurve.sign(num.toHex(msgHash), this.pk); return [num.toHex(e.r), num.toHex(e.s)]; }
}
class BraavosDeploySigner extends Signer {
  constructor(pk, impl) { super(pk); this.pk = pk; this.impl = impl; }
  async signRaw(msgHash) {
    const aux = [this.impl, 0, 0, 0, 0, 0, 0, 0, 0, 0, constants.StarknetChainId.SN_SEPOLIA].map(num.toHex);
    const a = ec.starkCurve.sign(hash.computePoseidonHashOnElements(aux), this.pk);
    const t = ec.starkCurve.sign(num.toHex(msgHash), this.pk);
    return [num.toHex(t.r), num.toHex(t.s), ...aux, num.toHex(a.r), num.toHex(a.s)];
  }
}

const deployer = () => {
  const d = JSON.parse(readFileSync(`${KEYS}/deployer-ecdsa.json`, "utf8"));
  return new Account({ provider, address: readFileSync(`${KEYS}/deployer-address.txt`, "utf8").trim(), signer: d.privateKey });
};
async function strkBalance(address) {
  const r = await retry(() => provider.callContract({ contractAddress: STRK, entrypoint: "balance_of", calldata: [address] }));
  return BigInt(r[0]) + (BigInt(r[1]) << 128n);
}
async function declared(h) { try { await provider.getClassByHash(h); return true; } catch { return false; } }
async function classAt(address) { try { return num.toHex(await retry(() => provider.getClassHashAt(address))); } catch { return null; } }
async function bounds(l2Max, dataMax = 5000n) {
  const b = await retry(() => provider.getBlockWithTxHashes("latest"));
  return {
    l1_gas: { max_amount: 0n, max_price_per_unit: BigInt(b.l1_gas_price.price_in_fri) * 2n },
    l1_data_gas: { max_amount: dataMax, max_price_per_unit: BigInt(b.l1_data_gas_price.price_in_fri) * 2n },
    l2_gas: { max_amount: l2Max, max_price_per_unit: (BigInt(b.l2_gas_price.price_in_fri) * 3n) / 2n },
  };
}
const boundFee = (b) => b.l2_gas.max_amount * b.l2_gas.max_price_per_unit + b.l1_data_gas.max_amount * b.l1_data_gas.max_price_per_unit;
const transferCall = (to, amount) => ({ contractAddress: STRK, entrypoint: "transfer", calldata: CallData.compile({ recipient: to, amount: cairo.uint256(amount) }) });
async function send(acc, calls, l2Max, dataMax) {
  const nonce = await retry(() => provider.getNonceForAddress(acc.address, "latest"));
  const t = await retry(async () => acc.execute(calls, { nonce, tip: TIP, resourceBounds: await bounds(l2Max, dataMax) }));
  const rc = await retry(() => provider.waitForTransaction(t.transaction_hash));
  return { tx: t.transaction_hash, fee: rc.actual_fee?.amount, l2Gas: rc.execution_resources?.l2_gas, status: rc.execution_status };
}
/** Tops `address` up so it can carry a transaction bounded at `l2Max`, plus 1 STRK. */
async function fund(address, l2Max, dataMax) {
  const need = boundFee(await bounds(l2Max, dataMax)) + 10n ** 18n;
  const have = await strkBalance(address);
  if (have < need) await send(deployer(), transferCall(address, need - have), 3000000n);
}

async function declareAll() {
  const acc = deployer();
  // starknet.js's default margin is +50% on amount and price (2.25x); the account must hold the
  // whole bound, so use a smaller one, as pf04_sepolia.mjs does.
  const margin = { max_amount: 10, max_price_per_unit: 25 };
  config.set("resourceBoundsOverhead", { l1_gas: margin, l2_gas: margin, l1_data_gas: margin });
  const maxFee = BigInt(process.env.PF13_MAX_FEE_STRK || "300") * 10n ** 18n;
  for (const name of CLASSES) {
    const classHash = H[name];
    if (await declared(classHash)) { log(`${name} ${classHash} already declared`); continue; }
    const contract = artifact(name, "contract_class"), casm = artifact(name, "compiled_contract_class");
    let resourceBounds;
    try {
      const estimate = await retry(() => acc.estimateDeclareFee({ contract, casm }, { skipValidate: false }));
      log(`${name}: estimated ${Number(estimate.overall_fee) / 1e18} STRK`);
      resourceBounds = estimate.resourceBounds;
    } catch (e) {
      // On 2026-11-26 the public RPC could not estimate a Sierra 1.10.0 declare ("Internal error")
      // while the gateway accepted only 1.10.0. Bound it by the code-size formula
      // (bench/pf04/summarize.py: 1,280 L2 gas per byte of code and ABI) + 20%, plus the
      // deployer's own validation.
      const code = 1280n * BigInt(32 * (casm.bytecode.length + contract.sierra_program.length) + JSON.stringify(contract.abi).length);
      resourceBounds = await bounds((code * 12n) / 10n + 20000000n);
      log(`${name}: no estimate (${JSON.stringify(e.baseError ?? "").slice(0, 80)}); formula bound ${resourceBounds.l2_gas.max_amount} L2 gas`);
    }
    const bound = boundFee(resourceBounds);
    log(`${name}: fee bound ${Number(bound) / 1e18} STRK`);
    if (bound > maxFee) throw new Error(`bound above PF13_MAX_FEE_STRK; not sending ${name}`);
    let d;
    // The RPC error echoes the whole class; keep only its code and message.
    try { d = await acc.declare({ contract, casm }, { tip: TIP, resourceBounds }); } catch (e) {
      throw new Error(`${name} declare refused: ${JSON.stringify(e.baseError ?? e.message?.slice(-500))}`);
    }
    const rc = await retry(() => provider.waitForTransaction(d.transaction_hash));
    (state.declares ||= {})[name] = { tx: d.transaction_hash, classHash, status: rc.execution_status }; save();
    log(`${name} declare ${rc.execution_status}: ${VOYAGER}/tx/${d.transaction_hash}, l2 gas ${rc.execution_resources?.l2_gas}`);
  }
}

function words(name) {
  const file = `${KEYS}/pf13-${name}-mnemonic.txt`;
  if (!existsSync(file)) writeFileSync(file, generateMnemonic(wordlist, 256));
  return readFileSync(file, "utf8").trim();
}

async function deploy(name, w, k) {
  const braavos = !!w.impl;
  const ctor = braavos ? [k.ecdsaPublicKey] : w.ctor(k.ecdsaPublicKey).map(num.toHex);
  const deployClass = braavos ? BRAAVOS_BASE : w.cls;
  const address = hash.calculateContractAddressFromHash(k.ecdsaPublicKey, deployClass, ctor, 0);
  const s = ((state.accounts ||= {})[name] ||= { address }); save();
  if (await classAt(address)) return s;
  await fund(address, 30000000n);
  const acc = new Account({ provider, address, signer: braavos ? new BraavosDeploySigner(k.ecdsaPrivateKey, w.impl) : k.ecdsaPrivateKey });
  const r = await retry(async () => acc.deployAccount({ classHash: deployClass, constructorCalldata: ctor, addressSalt: k.ecdsaPublicKey, contractAddress: address },
    { tip: TIP, resourceBounds: await bounds(30000000n) }));
  const rc = await retry(() => provider.waitForTransaction(r.transaction_hash));
  s.deploy = { tx: r.transaction_hash, status: rc.execution_status }; save();
  return s;
}

async function step(s, key, fn) {
  if (s[key]?.status === "SUCCEEDED") return true;
  if (s[key]) (s.failed ||= []).push({ [key]: s[key] });
  try { s[key] = await fn(); } catch (e) { s[key] = { error: errTail(e) }; }
  save();
  log(`  ${key}: ${s[key].tx ? `${VOYAGER}/tx/${s[key].tx} ` : ""}${s[key].status || s[key].error}${s[key].l2Gas ? `, l2 gas ${s[key].l2Gas}` : ""}`);
  return s[key].status === "SUCCEEDED";
}

async function runAccount(name) {
  const w = ACCOUNTS[name];
  const mnemonic = words(name);
  const roots = JSON.parse(readFileSync(ROOTS, "utf8"));
  const mldsa = prepareKeys(deriveAccountKeys(mnemonic, 0, w.profile, "ml-dsa-44"), roots);
  const falcon = prepareKeys(deriveAccountKeys(mnemonic, 0, w.profile, "falcon-512"), roots);
  log(`\n${name}`);
  const s = await deploy(name, w, mldsa);
  log(`  account ${s.address}`);
  const ecdsaAcc = new Account({ provider, address: s.address, signer: mldsa.ecdsaPrivateKey });

  if (w.viaFalcon) {
    // Migrate to the testnet-v1 class with Falcon-512 first, then move to ML-DSA-44 in one transaction.
    const ok = await step(s, "falconMigration", async () => {
      const info = await retry(() => inspectAccount(provider, s.address));
      if (!info.migratable) throw new Error(`not migratable: ${info.reason}`);
      await fund(s.address, V1_MIGRATION_L2_MAX);
      return send(ecdsaAcc, migrationCalls(info, falcon, { migratableClass: MIGRATABLE_CLASS, verifierClass: FALCON_VERIFIER, allowedVerifiers: KNOWN_VERIFIERS }), V1_MIGRATION_L2_MAX);
    });
    if (!ok) return;
    if (!(await step(s, "move", async () => {
      await fund(s.address, MOVE_L2_MAX, MOVE_DATA_MAX);
      s.balanceBeforeMove = (await strkBalance(s.address)).toString();
      return send(new Account({ provider, address: s.address, signer: new HybridSigner(falcon) }),
        setPqKeyCalls(s.address, falcon, mldsa, { verifierClass: VERIFIER, setupClass: SETUP, upgradeTo: V2, allowedVerifiers: MLDSA_ALLOWED }), MOVE_L2_MAX, MOVE_DATA_MAX);
    }))) return;
  } else if (!(await step(s, "move", async () => {
    const info = await retry(() => inspectAccount(provider, s.address));
    if (!info.migratable) throw new Error(`not migratable: ${info.reason}`);
    await fund(s.address, MOVE_L2_MAX, MOVE_DATA_MAX);
    s.balanceBeforeMove = (await strkBalance(s.address)).toString();
    return send(ecdsaAcc, migrationCalls(info, mldsa, { migratableClass: V2, verifierClass: VERIFIER, setupClass: SETUP, allowedVerifiers: MLDSA_ALLOWED }), MOVE_L2_MAX, MOVE_DATA_MAX);
  }))) return;

  const read = async (ep) => retry(() => provider.callContract({ contractAddress: s.address, entrypoint: ep, calldata: [] }, "latest"));
  const pq = (await read("get_falcon_public_key")).slice(1);
  s.after = {
    class: await classAt(s.address),
    ecdsaKeyMatchesWords: BigInt((await read("get_ecdsa_public_key"))[0]) === BigInt(mldsa.ecdsaPublicKey),
    mlDsaKeyMatchesWords: pq.length === 43 && pq.every((f, i) => BigInt(f) === BigInt(mldsa.falconFelts[i])),
    balanceDropEqualsFee: BigInt(s.balanceBeforeMove) - (await strkBalance(s.address)) === BigInt(s.move.fee),
  };
  save();
  log(`  after: ${JSON.stringify(s.after)}`);
  if (!(await step(s, "hybridTransfer", async () => {
    await fund(s.address, TRANSFER_L2_MAX);
    return send(new Account({ provider, address: s.address, signer: new HybridSigner(mldsa) }), transferCall(deployer().address, 10n ** 16n), TRANSFER_L2_MAX);
  }))) return;
  if (!s.ecdsaOnly) {
    try {
      const r = await send(new Account({ provider, address: s.address, signer: new EcdsaOnlySigner(mldsa.ecdsaPrivateKey) }), transferCall(deployer().address, 1n), TRANSFER_L2_MAX);
      s.ecdsaOnly = "UNEXPECTED: accepted " + r.tx;
    } catch (e) {
      const m = e?.message || String(e);
      s.ecdsaOnly = /validate/i.test(m) && /panicked|invalid signature|failed/i.test(m) ? "rejected in __validate__" : "UNCLEAR: " + errTail(e);
    }
    save();
  }
  log(`  ECDSA-only transfer: ${s.ecdsaOnly}`);
}

async function receipt(tx) {
  const rc = await retry(() => provider.getTransactionReceipt(tx));
  const blk = await retry(() => provider.getBlockWithTxHashes(rc.block_number));
  return {
    tx, status: rc.execution_status, block: rc.block_number, timestamp: blk.timestamp,
    l2_gas: Number(rc.execution_resources.l2_gas), l1_data_gas: Number(rc.execution_resources.l1_data_gas),
    l1_gas: Number(rc.execution_resources.l1_gas || 0), fee_fri: BigInt(rc.actual_fee.amount).toString(),
    l2_gas_price_fri: BigInt(blk.l2_gas_price.price_in_fri).toString(),
  };
}

async function receipts() {
  const out = { description: "PF-13 Sepolia receipts; see bench/pf13/README.md", generated_utc: new Date().toISOString(),
    classes: { HybridMigratableAccountV2: V2, HybridMlDsa44Verifier: VERIFIER, MlDsa44KeySetup: SETUP }, declares: {}, accounts: {} };
  for (const [name, d] of Object.entries(state.declares || {})) out.declares[name] = { classHash: d.classHash, ...(await receipt(d.tx)) };
  for (const [name, s] of Object.entries(state.accounts || {})) {
    const r = { address: s.address, path: ACCOUNTS[name].viaFalcon ? "falcon-512 testnet-v1 -> [upgrade V2, set_pq_key ML-DSA-44]" : "migrate straight to ML-DSA-44" };
    for (const k of ["deploy", "falconMigration", "move", "hybridTransfer"]) if (s[k]?.tx) r[k] = await receipt(s[k].tx);
    // Earlier attempts that reverted on chain (they paid a fee), or never reached the chain.
    r.failedAttempts = [];
    for (const f of s.failed || []) {
      const [step, a] = Object.entries(f)[0];
      r.failedAttempts.push({ step, ...(a.tx ? { ...(await receipt(a.tx)), revert_reason: (await retry(() => provider.getTransactionReceipt(a.tx))).revert_reason } : { error: a.error }) });
    }
    r.after = s.after ?? null;
    r.ecdsaOnlyTransfer = s.ecdsaOnly ?? null;
    out.accounts[name] = r;
  }
  writeFileSync(OUT, JSON.stringify(out, null, 2) + "\n");
  log(`wrote ${OUT}`);
}

async function plan() {
  const acc = deployer();
  log(`deployer ${acc.address}: ${Number(await strkBalance(acc.address)) / 1e18} STRK`);
  for (const c of CLASSES) log(`${c} ${H[c]} ${(await declared(H[c])) ? "declared" : "not declared"}`);
  log(`Falcon-512 verifier (testnet-v1): ${FALCON_VERIFIER}, migratable class ${MIGRATABLE_CLASS} ${(await declared(MIGRATABLE_CLASS)) ? "declared" : "NOT declared"}`);
  for (const name of Object.keys(ACCOUNTS)) {
    const s = state.accounts?.[name];
    log(`${name}: ${s ? ["deploy", "falconMigration", "move", "hybridTransfer"].map((k) => `${k}=${s[k]?.status || (s[k]?.error ? "error" : "-")}`).join(" ") + ` ecdsaOnly=${s.ecdsaOnly || "-"}` : "not started"}`);
  }
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd !== "--plan") TIP = (await retry(() => provider.getEstimateTip("latest", { maxBlocks: 10 }))).recommendedTip;
if (cmd === "--plan") await plan();
else if (cmd === "declare") await declareAll();
else if (cmd === "run") {
  for (const c of CLASSES) if (!(await declared(H[c]))) throw new Error(`${c} is not declared; run declare first`);
  for (const name of args.length ? args : Object.keys(ACCOUNTS)) { await runAccount(name); await sleep(2000); }
} else if (cmd === "receipts") await receipts();
else { console.error("usage: pf13_sepolia.mjs --plan | declare | run [name ...] | receipts"); process.exit(1); }
