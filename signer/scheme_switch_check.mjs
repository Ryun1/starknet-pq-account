// PF-13 step 1: checks, offline, that the kit's set_pq_key and V2 migration calldata is what the
// compiled HybridMigratableAccountV2 ABI expects, and that the set_pq_key proof signs the hash the
// Cairo tests verify on chain (run `scarb build` in contracts/ first).
//
//   node signer/scheme_switch_check.mjs
//
// The on-chain behaviour is tested in contracts/src/tests_scheme.cairo.
import { CallData, ec, num } from "starknet";
import { readFileSync } from "node:fs";
import { falcon512, falcon1024, makeNtt, publicKeyFelts } from "./falcon_adapter.mjs";
import { deriveAccountKeys } from "./pq_keys.mjs";
import { KNOWN_VERIFIERS, migrationArgs, rotationHash, setPqKeyCalls } from "./pq_account_kit.mjs";
import { ROOTS, ROTATION_FIXTURE, TARGET } from "./config.mjs";

const abi = (name) => JSON.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.contract_class.json`, "utf8")).abi;
const compile = (name, entrypoint, args) => new CallData(abi(name)).compile(entrypoint, args);
const same = (a, b) => a.length === b.length && a.every((x, i) => BigInt(x) === BigInt(b[i]));

let failed = 0;
const check = (name, ok, detail = "") => { if (!ok) failed++; console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ": " + detail : ""}`); };
const refuses = (name, fn, pattern) => {
  try { fn(); check(name, false, "did not throw"); } catch (e) { check(name, pattern.test(e.message), e.message); }
};

// The keys of rotation_fixture.mjs: ECDSA_PK with Falcon key A, rotating to Falcon key B.
const ntt = makeNtt(JSON.parse(readFileSync(ROOTS, "utf8")));
const falconKey = (fill) => {
  const { publicKey, secretKey } = falcon512.keygen(new Uint8Array(48).fill(fill));
  return { falconPublicKey: publicKey, falconSecretKey: secretKey, falconFelts: publicKeyFelts(publicKey, ntt).map(num.toHex) };
};
const ecdsaPrivateKey = "0x5eed03";
const ecdsa = { ecdsaPrivateKey, ecdsaPublicKey: num.toHex(ec.starkCurve.getStarkKey(ecdsaPrivateKey)) };
const current = { ...ecdsa, ...falconKey(7) };
const next = { ...ecdsa, ...falconKey(8) };

const ACCOUNT = "0x111", V2 = "0xa2", SETUP = "0x5e7";
const [SHAKE] = Object.keys(KNOWN_VERIFIERS);
const allowedVerifiers = { ...KNOWN_VERIFIERS, [SETUP]: "a setup class" };

const [call] = setPqKeyCalls(ACCOUNT, current, next, { verifierClass: SHAKE });
const proofLength = Number(BigInt(call.calldata[next.falconFelts.length + 3]));
const proof = call.calldata.slice(-proofLength);
check("set_pq_key calldata matches the V2 ABI", call.entrypoint === "set_pq_key" && call.contractAddress === ACCOUNT &&
  same(call.calldata, compile("HybridMigratableAccountV2", "set_pq_key",
    { pq_public_key: next.falconFelts, verifier_class_hash: SHAKE, setup_class_hash: "0x0", proof })));

const message = rotationHash(current.ecdsaPublicKey, next.falconFelts);
const fixtureHash = /FALCON_ROTATION_HASH: felt252 = (0x[0-9a-f]+);/.exec(readFileSync(ROTATION_FIXTURE, "utf8"))[1];
check("the proof's message is the rotation hash tests_scheme.cairo checks on chain", BigInt(message) === BigInt(fixtureHash), message);
check("the proof's ECDSA half is by the current classical key over that message",
  ec.starkCurve.verify(new ec.starkCurve.Signature(BigInt(proof[0]), BigInt(proof[1])), message.slice(2).padStart(64, "0"), ec.starkCurve.getPublicKey(ecdsaPrivateKey)));
check("the proof is a hybrid signature: 2 ECDSA felts and 60 Falcon felts", proof.length === 62);

const withSetup = setPqKeyCalls(ACCOUNT, current, next, { verifierClass: SHAKE, setupClass: SETUP, upgradeTo: V2, allowedVerifiers });
check("upgradeTo puts the class upgrade first in the same transaction", withSetup.length === 2 &&
  withSetup[0].entrypoint === "upgrade" && withSetup[0].calldata.join() === V2 && withSetup[1].entrypoint === "set_pq_key");
check("the setup class is passed after the verifier", BigInt(withSetup[1].calldata[next.falconFelts.length + 2]) === BigInt(SETUP));

refuses("verifier not in allowedVerifiers", () => setPqKeyCalls(ACCOUNT, current, next, { verifierClass: "0x999" }), /verifier class 0x999 is not in allowedVerifiers/);
refuses("setup class not in allowedVerifiers", () => setPqKeyCalls(ACCOUNT, current, next, { verifierClass: SHAKE, setupClass: SETUP }), /setup class 0x5e7 is not in allowedVerifiers/);

// Migration arguments: with a setup class the V2 layout, without one the earlier class's.
const split = (args, extra) => ({ proof: args.slice(current.falconFelts.length + 4 + extra) });
const v2Args = migrationArgs(current, SHAKE, "0x0");
check("migrate arguments with a setup class match the V2 ABI", same(v2Args, compile("HybridMigratableAccountV2", "migrate", {
  ecdsa_public_key: current.ecdsaPublicKey, pq_public_key: current.falconFelts, verifier_class_hash: SHAKE,
  setup_class_hash: "0x0", ...split(v2Args, 1) })));
const v1Args = migrationArgs(current, SHAKE);
check("migrate arguments without one still match the earlier class's ABI", same(v1Args, compile("HybridMigratableAccount", "migrate", {
  ecdsa_public_key: current.ecdsaPublicKey, falcon_public_key: current.falconFelts, verifier_class_hash: SHAKE, ...split(v1Args, 0) })));

// PF-14: Falcon-1024 through the same kit calls, with tests_falcon1024_fixture.cairo's key.
const F1024_FIXTURE = new URL("../contracts/src/tests_falcon1024_fixture.cairo", import.meta.url);
const ntt1024 = makeNtt(JSON.parse(readFileSync(new URL("./falcon1024_ntt_roots.json", import.meta.url), "utf8")));
const k1024 = falcon1024.keygen(new Uint8Array(48).fill(9));
const next1024 = { ...ecdsa, falconPublicKey: k1024.publicKey, falconSecretKey: k1024.secretKey,
  falconFelts: publicKeyFelts(k1024.publicKey, ntt1024).map(num.toHex) };
const F1024 = "0xf1024";
const [call1024] = setPqKeyCalls(ACCOUNT, current, next1024, { verifierClass: F1024, allowedVerifiers: { ...KNOWN_VERIFIERS, [F1024]: "Falcon-1024" } });
const proof1024 = call1024.calldata.slice(-Number(BigInt(call1024.calldata[57 + 3])));
check("Falcon-1024: a 57-felt key and a 118-felt proof", next1024.falconFelts.length === 57 && proof1024.length === 118);
check("Falcon-1024: set_pq_key calldata matches the V2 ABI", same(call1024.calldata, compile("HybridMigratableAccountV2", "set_pq_key",
  { pq_public_key: next1024.falconFelts, verifier_class_hash: F1024, setup_class_hash: "0x0", proof: proof1024 })));
const f1024Hash = /F1024_ROTATION_HASH: felt252 =\s*(0x[0-9a-f]+);/.exec(readFileSync(F1024_FIXTURE, "utf8"))[1];
check("Falcon-1024: the proof signs the rotation hash tests_scheme.cairo checks on chain",
  BigInt(rotationHash(current.ecdsaPublicKey, next1024.falconFelts)) === BigInt(f1024Hash));
check("the 1024 roots give the same Falcon-512 key felts as the 512 roots",
  same(publicKeyFelts(current.falconPublicKey, ntt1024), current.falconFelts));

// Backup profile v0.2 (Falcon-1024): deterministic, and v0.1 unchanged by the scheme argument.
const WORDS = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const v01 = deriveAccountKeys(WORDS, 0, "pq");
const v02 = deriveAccountKeys(WORDS, 0, "pq", "falcon-1024");
check("backup v0.2 gives a Falcon-1024 key with the same ECDSA key", v02.falconPublicKey.length === 1793 &&
  v02.falconPublicKey[0] === 0x0a && v02.ecdsaPublicKey === v01.ecdsaPublicKey);
check("backup v0.2 is deterministic", same([...v02.falconPublicKey], [...deriveAccountKeys(WORDS, 0, "pq", "falcon-1024").falconPublicKey]));
check("backup v0.1 is unchanged by the scheme argument", same([...v01.falconPublicKey], [...deriveAccountKeys(WORDS, 0, "pq", "falcon-512").falconPublicKey]));

process.exit(failed ? 1 : 0);
