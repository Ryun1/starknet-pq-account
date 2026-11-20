// ARCH-01: checks, offline, the kit's PQ-only calls against the compiled HybridMigratableAccountV2
// ABI, their proofs against the hashes tests_pq_only.cairo verifies on chain, the kit's gates, and
// that PQ_ONLY_VERIFIERS are the compiled classes' hashes (run `scarb build` in contracts/ first).
//
//   node signer/pq_only_check.mjs
import { CallData, ec, hash, num } from "starknet";
import { readFileSync } from "node:fs";
import { falcon512, makeNtt, publicKeyFelts } from "./falcon_adapter.mjs";
import { HybridSigner, KNOWN_VERIFIERS, PQ_ONLY_VERIFIERS, hybridModeCalls, pqOnlyCalls, rotationHash } from "./pq_account_kit.mjs";
import { ROOTS, ROTATION_FIXTURE, TARGET } from "./config.mjs";

const cls = (name) => JSON.parse(readFileSync(`${TARGET}/pq_hybrid_${name}.contract_class.json`, "utf8"));
const v2 = new CallData(cls("HybridMigratableAccountV2").abi);
const same = (a, b) => a.length === b.length && a.every((x, i) => BigInt(x) === BigInt(b[i]));
const fixture = (file, name) => new RegExp(`${name}: felt252 =\\s*(0x[0-9a-f]+);`).exec(readFileSync(file, "utf8"))[1];

let failed = 0;
const check = (name, ok, detail = "") => { if (!ok) failed++; console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ": " + detail : ""}`); };
const refuses = (name, fn, pattern) => {
  try { fn(); check(name, false, "did not throw"); } catch (e) { check(name, pattern.test(e.message), e.message); }
};

const [PQ512, PQ1024] = Object.keys(PQ_ONLY_VERIFIERS);
check("PQ_ONLY_VERIFIERS[0] is the compiled FalconOnlyVerifierPfSmall", BigInt(PQ512) === BigInt(hash.computeSierraContractClassHash(cls("FalconOnlyVerifierPfSmall"))));
check("PQ_ONLY_VERIFIERS[1] is the compiled FalconOnlyVerifierFalcon1024", BigInt(PQ1024) === BigInt(hash.computeSierraContractClassHash(cls("FalconOnlyVerifierFalcon1024"))));

// The keys of the fixtures: ECDSA_PK (0x5eed03) and WRONG_ECDSA_PK (0x5eed04), Falcon key A.
const ntt = makeNtt(JSON.parse(readFileSync(ROOTS, "utf8")));
const { publicKey, secretKey } = falcon512.keygen(new Uint8Array(48).fill(7));
const falcon = { falconPublicKey: publicKey, falconSecretKey: secretKey, falconFelts: publicKeyFelts(publicKey, ntt).map(num.toHex) };
const ecdsa = (priv) => ({ ecdsaPrivateKey: priv, ecdsaPublicKey: num.toHex(ec.starkCurve.getStarkKey(priv)) });
const current = { ...ecdsa("0x5eed03"), ...falcon };
const next = { ...ecdsa("0x5eed04"), ...falcon };
const ACCOUNT = "0x111", V2 = "0xa2";
const [SHAKE] = Object.keys(KNOWN_VERIFIERS);
const split = (calldata, keyLen) => calldata.slice(keyLen + 4);

// Entering PQ-only.
refuses("pqOnlyCalls refuses without acceptUnreviewedVerifier", () => pqOnlyCalls(ACCOUNT, current, { verifierClass: PQ512 }), /acceptUnreviewedVerifier/);
refuses("pqOnlyCalls refuses a hybrid verifier", () => pqOnlyCalls(ACCOUNT, current, { verifierClass: SHAKE, acceptUnreviewedVerifier: true }), /not in allowedVerifiers/);
const enter = pqOnlyCalls(ACCOUNT, current, { verifierClass: PQ512, upgradeTo: V2, acceptUnreviewedVerifier: true });
const enterProof = split(enter[1].calldata, 29);
check("pqOnlyCalls: upgrade first, then set_pq_key", enter.length === 2 && enter[0].entrypoint === "upgrade" && enter[1].entrypoint === "set_pq_key");
check("pqOnlyCalls: set_pq_key calldata matches the V2 ABI, same key, Falcon-only verifier", same(enter[1].calldata,
  v2.compile("set_pq_key", { pq_public_key: current.falconFelts, verifier_class_hash: PQ512, setup_class_hash: "0x0", proof: enterProof })));
check("pqOnlyCalls: the proof is Falcon alone (60 felts)", enterProof.length === 60);
check("pqOnlyCalls: the proof signs the hash tests_pq_only.cairo checks",
  BigInt(rotationHash(current.ecdsaPublicKey, current.falconFelts)) === BigInt(fixture(new URL("../contracts/src/tests_pq_only_fixture.cairo", import.meta.url), "PQ_ONLY_ROTATION_HASH")));

// Leaving PQ-only.
refuses("hybridModeCalls refuses the old ECDSA key", () => hybridModeCalls(ACCOUNT, current, current, { verifierClass: SHAKE }), /new ECDSA key/);
refuses("hybridModeCalls refuses a verifier not in allowedVerifiers", () => hybridModeCalls(ACCOUNT, current, next, { verifierClass: "0x999" }), /not in allowedVerifiers/);
const [rotate, set] = hybridModeCalls(ACCOUNT, current, next, { verifierClass: SHAKE });
const rotateProof = rotate.calldata.slice(2);
const setProof = split(set.calldata, 29);
check("hybridModeCalls: rotate_ecdsa_public_key matches the V2 ABI", rotate.entrypoint === "rotate_ecdsa_public_key" &&
  same(rotate.calldata, v2.compile("rotate_ecdsa_public_key", { ecdsa_public_key: next.ecdsaPublicKey, proof: rotateProof })));
check("hybridModeCalls: its proof is Falcon alone, for the PQ-only verifier", rotateProof.length === 60);
check("hybridModeCalls: set_pq_key matches the V2 ABI", set.entrypoint === "set_pq_key" &&
  same(set.calldata, v2.compile("set_pq_key", { pq_public_key: next.falconFelts, verifier_class_hash: SHAKE, setup_class_hash: "0x0", proof: setProof })));
const message = rotationHash(next.ecdsaPublicKey, next.falconFelts);
check("hybridModeCalls: both proofs sign the hash tests_pq_only.cairo checks", BigInt(message) === BigInt(fixture(ROTATION_FIXTURE, "ECDSA_ROTATION_HASH")));
check("hybridModeCalls: set_pq_key's proof is hybrid, its ECDSA half by the NEW key", setProof.length === 62 &&
  ec.starkCurve.verify(new ec.starkCurve.Signature(BigInt(setProof[0]), BigInt(setProof[1])), message.slice(2).padStart(64, "0"), ec.starkCurve.getPublicKey("0x5eed04")));

// Signer.
const tx = "0x1234";
check("HybridSigner signs hybrid by default (62 felts)", (await new HybridSigner(current).signRaw(tx)).length === 62);
check("HybridSigner({ pqOnly: true }) signs Falcon alone (60 felts)", (await new HybridSigner(current, { pqOnly: true }).signRaw(tx)).length === 60);

process.exit(failed ? 1 : 0);
