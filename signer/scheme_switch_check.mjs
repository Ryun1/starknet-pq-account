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
import { HybridSigner, KNOWN_VERIFIERS, migrationArgs, prepareKeys, rotationHash, setPqKeyCalls } from "./pq_account_kit.mjs";
import { hashBytes, ml_dsa44 } from "./mldsa_adapter.mjs";
import { hkdf } from "@noble/hashes/hkdf";
import { sha512 } from "@noble/hashes/sha2";
import { mnemonicToSeedSync } from "@scure/bip39";
import { createHash } from "node:crypto";
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

// PF-13: ML-DSA-44 through the same kit calls, against tests_mldsa_fixture.cairo (seed 13, ECDSA_PK).
const MLDSA_FIXTURE = readFileSync(new URL("../contracts/src/tests_mldsa_fixture.cairo", import.meta.url), "utf8");
const cairoArray = (fn) => [...new RegExp(`pub fn ${fn}\\(\\) -> Array<felt252> \\{\\s*array!\\[([^\\]]*)\\]`).exec(MLDSA_FIXTURE)[1].matchAll(/0x[0-9a-f]+/g)].map((m) => m[0]);
const km = ml_dsa44.keygen(new Uint8Array(32).fill(13));
const nextMl = prepareKeys({ ...ecdsa, falconPublicKey: km.publicKey, falconSecretKey: km.secretKey });
check("ML-DSA-44: prepareKeys gives the fixture's 43-felt key", same(nextMl.falconFelts, cairoArray("mldsa_pk")));
const MLDSA = "0x3d5a44", MLSETUP = "0x5e7d5a";
const allowMl = { ...KNOWN_VERIFIERS, [MLDSA]: "ML-DSA-44", [MLSETUP]: "ML-DSA-44 setup" };
const [callMl] = setPqKeyCalls(ACCOUNT, current, nextMl, { verifierClass: MLDSA, setupClass: MLSETUP, allowedVerifiers: allowMl });
const proofMl = callMl.calldata.slice(43 + 4);
check("ML-DSA-44: set_pq_key calldata matches the V2 ABI", same(callMl.calldata, compile("HybridMigratableAccountV2", "set_pq_key",
  { pq_public_key: nextMl.falconFelts, verifier_class_hash: MLDSA, setup_class_hash: MLSETUP, proof: proofMl })));
check("ML-DSA-44: the kit's proof is the fixture's, which tests_scheme.cairo accepts on chain", same(proofMl, cairoArray("mldsa_rotation_proof")));
const MSG = /REGISTRATION_HASH: felt252 =\s*(0x[0-9a-f]+);/.exec(readFileSync(new URL("../contracts/src/tests_wallets_fixture.cairo", import.meta.url), "utf8"))[1];
check("ML-DSA-44: HybridSigner signs a transaction hash as the fixture does",
  same(await new HybridSigner(nextMl).signRaw(MSG), cairoArray("mldsa_sig")));

// Backup profile v0.2 (ML-DSA-44): FIPS 204 KeyGen_internal, checked against NIST's ACVP keyGen cases.
const acvp = JSON.parse(readFileSync(new URL("../bench/pf13/acvp_keygen.json", import.meta.url), "utf8")).tests;
const sha = (b) => createHash("sha256").update(b).digest("hex");
const acvpBad = acvp.filter((t) => { const k = ml_dsa44.keygen(Buffer.from(t.seed, "hex")); return sha(k.publicKey) !== t.pk_sha256 || sha(k.secretKey) !== t.sk_sha256; });
check(`ML-DSA-44: noble keygen matches all ${acvp.length} NIST ACVP keyGen cases`, acvp.length === 25 && acvpBad.length === 0, acvpBad.map((t) => t.tcId).join(","));
const v02ml = deriveAccountKeys(WORDS, 0, "pq", "ml-dsa-44");
check("backup v0.2 gives an ML-DSA-44 key with the same ECDSA key", v02ml.falconPublicKey.length === 1312 && v02ml.ecdsaPublicKey === v01.ecdsaPublicKey);
check("backup v0.2 ML-DSA-44 vector", sha(v02ml.falconPublicKey) === "ac0882837d8d1a2f1b2fba51c5cb0c1403b1acbb64d951e1bd522ed6c936e599", sha(v02ml.falconPublicKey));
check("backup v0.2 Falcon-1024 key is unchanged by the ML-DSA-44 entry",
  sha(v02.falconPublicKey) === "d14527e61098ec1c65435148886c783d064dd193339720d3d5b544b4ecff864a");

// The browser page's ML-DSA-44 block (signer/browser-wallet.template.html), run here as written:
// its keys, key felts and signatures must be the kit's.
const PAGE = readFileSync(new URL("./browser-wallet.template.html", import.meta.url), "utf8");
const block = /\/\/ --- ML-DSA-44 \(PF-13\)[^\n]*\n([\s\S]*?)\/\/ --- end ML-DSA-44 ---/.exec(PAGE)[1];
const page = new Function("ml_dsa44", "hkdf", "sha512", `${block}; return { mldsaKeysFromSeed, bytesToFelts, mldsaSignatureFelts };`)(ml_dsa44, hkdf, sha512);
const pageKeys = page.mldsaKeysFromSeed(mnemonicToSeedSync(WORDS), 0);
check("page: ML-DSA-44 key from the words = backup v0.2's", same([...pageKeys.falconPublicKey], [...v02ml.falconPublicKey]));
check("page: key felts = the kit's", same(page.bytesToFelts(km.publicKey), nextMl.falconFelts));
const pageSig = page.mldsaSignatureFelts(MSG, km.secretKey);
// Inverse of the packing: 31 little-endian bytes per felt, the last felt the rest.
const feltsToBytes = (felts, n) => Uint8Array.from({ length: n }, (_, k) => Number((felts[Math.floor(k / 31)] >> BigInt(8 * (k % 31))) & 0xffn));
check("page: its signature felts unpack to a signature noble accepts",
  pageSig.length === 79 && ml_dsa44.verify(feltsToBytes(pageSig, 2420), hashBytes(MSG), km.publicKey));

process.exit(failed ? 1 : 0);
