// PF-14 on Sepolia: the Falcon-1024 public demo account for docs/index.html, and its receipts.
// TESTNET ONLY. The words are the page's public demo words (account index 1, backup profile v0.2),
// published on purpose; the account holds Sepolia STRK with no value.
//
//   (cd contracts && scarb build)
//   node pf04_sepolia.mjs declare HybridMigratableAccountV2       # once per network, from the deployer
//   node pf04_sepolia.mjs declare HybridShakeVerifierFalcon1024   # about 4.43e9 L2 gas, ~100 STRK
//   node falcon1024_demo_setup.mjs                                # this script; rerun to resume
//
// 1. checks both classes are declared (the hashes of the built artifacts)
// 2. OZ account for the demo words at index 1: funded by the deployer, deployed
// 3. one transaction from it, signed with ECDSA: [upgrade(V2), migrate(ecdsa, Falcon-1024 key,
//    Falcon-1024 verifier, no setup, proof)]
// 4. a hybrid ECDSA + Falcon-1024 transfer, then an ECDSA-only transfer, which must be rejected
// Writes bench/pf14/sepolia.json: transaction hashes and receipts, never keys.
import { Account, CallData, RpcProvider, Signer, cairo, ec, hash, json, num } from "starknet";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { HybridSigner, deriveAccountKeys, migrationArgs, prepareKeys } from "./pq_account_kit.mjs";
import { KEYS, RPC, TARGET } from "./config.mjs";

const provider = new RpcProvider({ nodeUrl: RPC });
const STATE_FILE = `${KEYS}/falcon1024-demo-state.json`;
const OUT = new URL("../bench/pf14/sepolia.json", import.meta.url);
const VOYAGER = "https://sepolia.voyager.online";
const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const OZ_ACCOUNT_CLASS = "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";
const FUND = 30n * 10n ** 18n;
const INDEX = 1;
// A cap, not the fee: about 60M is expected on Sepolia (bench/pf14), and starknet-devnet 0.9.0
// counts about 2.4 times what Sepolia charged for the same Falcon-512 transfer.
const TRANSFER_L2_MAX = 250000000n;
const template = readFileSync(new URL("./browser-wallet.template.html", import.meta.url), "utf8");
const WORDS = template.match(/const PUBLIC_DEMO_MNEMONIC = "([^"]+)"/)[1];
const ROOTS = JSON.parse(readFileSync(new URL("./falcon1024_ntt_roots.json", import.meta.url), "utf8"));

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
const V2 = classHashOf("HybridMigratableAccountV2");
const VERIFIER = classHashOf("HybridShakeVerifierFalcon1024");
for (const [name, h] of [["HybridMigratableAccountV2", V2], ["HybridShakeVerifierFalcon1024", VERIFIER]]) {
  try { await provider.getClassByHash(h); console.log(`${name} ${h} declared`); } catch {
    console.error(`${name} ${h} is not declared on Sepolia: node pf04_sepolia.mjs declare ${name}`);
    process.exit(1);
  }
}

// 2. account
const keys = prepareKeys(deriveAccountKeys(WORDS, INDEX, "pq", "falcon-1024"), ROOTS);
const address = hash.calculateContractAddressFromHash(keys.ecdsaPublicKey, OZ_ACCOUNT_CLASS, [keys.ecdsaPublicKey], 0);
state.address = address; save();
console.log("Falcon-1024 demo account:", address);
const deployer = JSON.parse(readFileSync(`${KEYS}/deployer-ecdsa.json`, "utf8"));
const deployerAddress = readFileSync(`${KEYS}/deployer-address.txt`, "utf8").trim();
const deployerAcc = new Account({ provider, address: deployerAddress, signer: deployer.privateKey });
if ((await classAt(address)) === null) {
  if ((await balance(address)) < FUND / 2n) {
    console.log("funding from the deployer");
    await send(deployerAcc, transferCall(address, FUND), 10000000n);
  }
  const oz = new Account({ provider, address, signer: keys.ecdsaPrivateKey });
  const r = await oz.deployAccount({ classHash: OZ_ACCOUNT_CLASS, constructorCalldata: [keys.ecdsaPublicKey], addressSalt: keys.ecdsaPublicKey, contractAddress: address }, { tip: await tip() });
  await provider.waitForTransaction(r.transaction_hash);
  state.deployTx = r.transaction_hash; save();
  console.log("OZ account deployed:", `${VOYAGER}/tx/${r.transaction_hash}`);
  await sleep(2000);
}

// 3. migration straight to Falcon-1024, signed by the account's current ECDSA key
if ((await classAt(address)) === BigInt(OZ_ACCOUNT_CLASS)) {
  console.log("migrating to HybridMigratableAccountV2 with the Falcon-1024 verifier");
  const oz = new Account({ provider, address, signer: keys.ecdsaPrivateKey });
  state.migrationTx = await send(oz, [
    { contractAddress: address, entrypoint: "upgrade", calldata: [V2] },
    { contractAddress: address, entrypoint: "migrate", calldata: migrationArgs(keys, VERIFIER, "0x0") },
  ], 250000000n, 20000n);
  save();
  await sleep(2000);
}
if ((await classAt(address)) !== BigInt(V2)) throw new Error("account is not on HybridMigratableAccountV2");

// 4. hybrid transfer, then ECDSA only
if (!state.hybridTransferTx) {
  console.log("hybrid ECDSA + Falcon-1024 transfer");
  state.hybridTransferTx = await send(new Account({ provider, address, signer: new HybridSigner(keys) }), transferCall(deployerAddress, 10n ** 16n), TRANSFER_L2_MAX);
  save();
}
if (!state.ecdsaOnlyRejected) {
  console.log("ECDSA-only transfer (must be rejected)");
  class EcdsaOnly extends Signer {
    async signRaw(h) { const e = ec.starkCurve.sign(num.toHex(h), keys.ecdsaPrivateKey); return [num.toHex(e.r), num.toHex(e.s)]; }
  }
  try {
    const hash_ = await send(new Account({ provider, address, signer: new EcdsaOnly(keys.ecdsaPrivateKey) }), transferCall(deployerAddress, 10n ** 16n), TRANSFER_L2_MAX);
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
  description: "PF-14 Falcon-1024 public demo account on Sepolia (signer/falcon1024_demo_setup.mjs); transaction hashes and receipts only",
  account: address,
  classes: { HybridMigratableAccountV2: V2, HybridShakeVerifierFalcon1024: VERIFIER },
  deploy: state.deployTx ? await receipt(state.deployTx) : null,
  migration: state.migrationTx ? await receipt(state.migrationTx) : null,
  hybrid_transfer: await receipt(state.hybridTransferTx),
  ecdsa_only_transfer: { rejected: true, error_tail: state.ecdsaOnlyRejected },
}, null, 2) + "\n");
console.log("wrote", OUT.pathname, "balance", Number(await balance(address)) / 1e18, "STRK");
