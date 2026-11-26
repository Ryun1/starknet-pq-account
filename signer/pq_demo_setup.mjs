// Public demo accounts for docs/index.html on Sepolia, one per PQ scheme beyond Falcon-512, and their
// receipts. TESTNET ONLY. The words are the page's public demo words (backup profile v0.2), published
// on purpose; the accounts hold Sepolia STRK with no value.
//
//   (cd contracts && scarb build)            # Sepolia takes Sierra 1.10.0 only: scarb 2.22.0
//   node pq_demo_setup.mjs ml-dsa-44         # index 2; classes from bench/pf13/sepolia.json (PF-13)
//   node pq_demo_setup.mjs falcon-1024       # index 1; first: node pf04_sepolia.mjs declare HybridShakeVerifierFalcon1024
//   rerun to resume (state in .keys/<scheme>-demo-state.json)
//
// 1. checks the classes are declared
// 2. OZ account for the demo words at the scheme's index: funded by the deployer, deployed
// 3. one transaction from it, signed with ECDSA: [upgrade(V2), migrate(ecdsa, PQ key, verifier,
//    setup, proof)]
// 4. a hybrid transfer, then an ECDSA-only transfer, which must be rejected
// Writes the scheme's demo receipts: transaction hashes and receipts, never keys.
import { Account, CallData, RpcProvider, Signer, cairo, ec, hash, json, num } from "starknet";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { HybridSigner, deriveAccountKeys, migrationArgs, prepareKeys } from "./pq_account_kit.mjs";
import { KEYS, RPC, TARGET } from "./config.mjs";

const provider = new RpcProvider({ nodeUrl: RPC });
const SCHEME = process.argv[2];
// V2 and the ML-DSA-44 classes as declared by PF-13 step 10 (a scarb 2.22.0 build; a local build with
// another toolchain hashes differently). Falcon-1024 from the build in TARGET.
const PF13 = JSON.parse(readFileSync(new URL("../bench/pf13/sepolia.json", import.meta.url), "utf8")).classes;
const SCHEMES = {
  "ml-dsa-44": { index: 2, out: "../bench/pf13/demo-sepolia.json", verifier: ["HybridMlDsa44Verifier", PF13.HybridMlDsa44Verifier],
    setup: ["MlDsa44KeySetup", PF13.MlDsa44KeySetup], migrationL2: 1200000000n, migrationData: 60000n, transferL2: 120000000n, fund: 100n * 10n ** 18n },
  "falcon-1024": { index: 1, out: "../bench/pf14/sepolia.json", verifier: ["HybridShakeVerifierFalcon1024", null],
    setup: null, migrationL2: 250000000n, migrationData: 20000n, transferL2: 250000000n, fund: 30n * 10n ** 18n },
};
const S = SCHEMES[SCHEME];
if (!S) { console.error(`usage: node pq_demo_setup.mjs ${Object.keys(SCHEMES).join(" | ")}`); process.exit(1); }
const STATE_FILE = `${KEYS}/${SCHEME}-demo-state.json`;
const OUT = new URL(S.out, import.meta.url);
const VOYAGER = "https://sepolia.voyager.online";
const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const OZ_ACCOUNT_CLASS = "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";
const template = readFileSync(new URL("./browser-wallet.template.html", import.meta.url), "utf8");
const WORDS = template.match(/const PUBLIC_DEMO_MNEMONIC = "([^"]+)"/)[1];
const ROOTS = JSON.parse(readFileSync(new URL("./falcon1024_ntt_roots.json", import.meta.url), "utf8")); // unused for ML-DSA-44

const state = existsSync(STATE_FILE) ? JSON.parse(readFileSync(STATE_FILE, "utf8")) : {};
const save = () => writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const classHashOf = (name) => hash.computeContractClassHash(json.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.contract_class.json`, "utf8")));
const transferCall = (to, amount) => ({ contractAddress: STRK, entrypoint: "transfer", calldata: CallData.compile({ recipient: to, amount: cairo.uint256(amount) }) });
async function balance(a) {
  const r = await provider.callContract({ contractAddress: STRK, entrypoint: "balance_of", calldata: [a] }, "latest");
  return BigInt(r[0]) + (BigInt(r[1]) << 128n);
}
async function classAt(a) { try { return BigInt(await provider.getClassHashAt(a)); } catch { return null; } }
async function bounds(l2Max, dataMax) {
  const b = await provider.getBlockWithTxHashes("latest");
  return {
    l1_gas: { max_amount: 0n, max_price_per_unit: BigInt(b.l1_gas_price.price_in_fri) * 2n },
    l1_data_gas: { max_amount: dataMax, max_price_per_unit: BigInt(b.l1_data_gas_price.price_in_fri) * 2n },
    l2_gas: { max_amount: l2Max, max_price_per_unit: (BigInt(b.l2_gas_price.price_in_fri) * 3n) / 2n },
  };
}
const tip = async () => (await provider.getEstimateTip("latest", { maxBlocks: 5 })).recommendedTip;
// dataMax: L1 data gas for the state diff. The migration writes the 57-felt key (about 6,000).
async function send(acc, calls, l2Max, dataMax = 5000n) {
  const nonce = await provider.getNonceForAddress(acc.address, "latest");
  const r = await acc.execute(calls, { nonce, tip: await tip(), resourceBounds: await bounds(l2Max, dataMax) });
  const rc = await provider.waitForTransaction(r.transaction_hash);
  if (rc.execution_status !== "SUCCEEDED") throw new Error(`${r.transaction_hash} ${rc.execution_status} ${rc.revert_reason || ""}`);
  console.log(`  ${VOYAGER}/tx/${r.transaction_hash}  l2 gas ${rc.execution_resources?.l2_gas}`);
  return r.transaction_hash;
}

// 1. classes
const V2 = PF13.HybridMigratableAccountV2;
const VERIFIER = S.verifier[1] || classHashOf(S.verifier[0]);
const SETUP = S.setup ? S.setup[1] : "0x0";
const classes = { HybridMigratableAccountV2: V2, [S.verifier[0]]: VERIFIER, ...(S.setup ? { [S.setup[0]]: SETUP } : {}) };
for (const [name, h] of Object.entries(classes)) {
  try { await provider.getClassByHash(h); console.log(`${name} ${h} declared`); } catch {
    console.error(`${name} ${h} is not declared on Sepolia: node pf04_sepolia.mjs declare ${name}`);
    process.exit(1);
  }
}

// 2. account
const keys = prepareKeys(deriveAccountKeys(WORDS, S.index, "pq", SCHEME), ROOTS);
const address = hash.calculateContractAddressFromHash(keys.ecdsaPublicKey, OZ_ACCOUNT_CLASS, [keys.ecdsaPublicKey], 0);
state.address = address; save();
console.log(`${SCHEME} demo account (index ${S.index}):`, address);
const deployer = JSON.parse(readFileSync(`${KEYS}/deployer-ecdsa.json`, "utf8"));
const deployerAddress = readFileSync(`${KEYS}/deployer-address.txt`, "utf8").trim();
const deployerAcc = new Account({ provider, address: deployerAddress, signer: deployer.privateKey });
if ((await classAt(address)) === null) {
  if ((await balance(address)) < S.fund / 2n) {
    console.log("funding from the deployer");
    await send(deployerAcc, transferCall(address, S.fund), 10000000n);
  }
  const oz = new Account({ provider, address, signer: keys.ecdsaPrivateKey });
  const r = await oz.deployAccount({ classHash: OZ_ACCOUNT_CLASS, constructorCalldata: [keys.ecdsaPublicKey], addressSalt: keys.ecdsaPublicKey, contractAddress: address }, { tip: await tip() });
  await provider.waitForTransaction(r.transaction_hash);
  state.deployTx = r.transaction_hash; save();
  console.log("OZ account deployed:", `${VOYAGER}/tx/${r.transaction_hash}`);
  await sleep(2000);
}

// 3. migration straight to the scheme, signed by the account's current ECDSA key. ML-DSA-44's setup
// writes the 419-slot cache (45K L1 data gas). From this OpenZeppelin class it costs 1.12e9 L2 gas on
// Sepolia (2026-11-26 trace: setup 905M, proof 73M), against 459M from Argent 0.5.0 in
// bench/pf13/sepolia.json: probably because this older class runs the transaction metered in Cairo steps.
// Sepolia caps a transaction at 1.21e9, so this is close to the limit.
if ((await classAt(address)) === BigInt(OZ_ACCOUNT_CLASS)) {
  if ((await balance(address)) < S.fund / 2n) {
    console.log("topping up from the deployer");
    await send(deployerAcc, transferCall(address, S.fund / 2n), 10000000n);
  }
  console.log(`migrating to HybridMigratableAccountV2 with ${S.verifier[0]}`);
  const oz = new Account({ provider, address, signer: keys.ecdsaPrivateKey });
  state.migrationTx = await send(oz, [
    { contractAddress: address, entrypoint: "upgrade", calldata: [V2] },
    { contractAddress: address, entrypoint: "migrate", calldata: migrationArgs(keys, VERIFIER, SETUP) },
  ], S.migrationL2, S.migrationData);
  save();
  await sleep(2000);
}
if ((await classAt(address)) !== BigInt(V2)) throw new Error("account is not on HybridMigratableAccountV2");

// 4. hybrid transfer, then ECDSA only
if (!state.hybridTransferTx) {
  console.log(`hybrid ECDSA + ${SCHEME} transfer`);
  state.hybridTransferTx = await send(new Account({ provider, address, signer: new HybridSigner(keys) }), transferCall(deployerAddress, 10n ** 16n), S.transferL2);
  save();
}
if (!state.ecdsaOnlyRejected) {
  console.log("ECDSA-only transfer (must be rejected)");
  class EcdsaOnly extends Signer {
    async signRaw(h) { const e = ec.starkCurve.sign(num.toHex(h), keys.ecdsaPrivateKey); return [num.toHex(e.r), num.toHex(e.s)]; }
  }
  try {
    const hash_ = await send(new Account({ provider, address, signer: new EcdsaOnly(keys.ecdsaPrivateKey) }), transferCall(deployerAddress, 10n ** 16n), S.transferL2);
    throw new Error(`ECDSA-only transfer was ACCEPTED: ${hash_}`);
  } catch (e) {
    const m = String(e.message || e);
    if (/ACCEPTED/.test(m) || !/validate|signature/i.test(m)) throw e;
    state.ecdsaOnlyRejected = m.slice(Math.max(0, m.length - 300)); save();
    console.log("  rejected in validation, as expected");
  }
}

// receipts
const receipt = async (tx) => {
  const rc = await provider.getTransactionReceipt(tx);
  return { tx, status: rc.execution_status, l2_gas: Number(rc.execution_resources?.l2_gas ?? 0), fee_fri: BigInt(rc.actual_fee.amount).toString() };
};
writeFileSync(OUT, JSON.stringify({
  description: `${SCHEME} public demo account on Sepolia (signer/pq_demo_setup.mjs, demo words index ${S.index}); transaction hashes and receipts only`,
  account: address,
  classes,
  deploy: state.deployTx ? await receipt(state.deployTx) : null,
  migration: state.migrationTx ? await receipt(state.migrationTx) : null,
  hybrid_transfer: await receipt(state.hybridTransferTx),
  ecdsa_only_transfer: { rejected: true, error_tail: state.ecdsaOnlyRejected },
}, null, 2) + "\n");
console.log("wrote", OUT.pathname, "balance", Number(await balance(address)) / 1e18, "STRK");
