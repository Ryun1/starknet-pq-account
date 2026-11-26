// The testnet release manifest: every deployed class tied to its artifacts, sources and toolchain.
// TESTNET ONLY.
//
//   cd contracts && scarb build && cd ..
//   node scripts/release_manifest.mjs --check      # offline: artifacts and patches match the manifest
//   node scripts/release_manifest.mjs --chain      # read-only, Sepolia: classes declared, guard deployed
//   node scripts/release_manifest.mjs --write [--commit]   # rebuild it from contracts/target/dev
//
// --release NAME picks the release (testnet-v1, the default, or testnet-v2); build each with the
// toolchain its RELEASES entry records. --manifest PATH checks another copy. --write keeps the
// recorded declare transactions, guard instance and source commit; --commit records the current
// git HEAD instead.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
// starknet.js is installed in signer/, not next to this script. import() takes a URL, not a path
// (a bare Windows path is read as a scheme).
const { RpcProvider, hash } = await import(pathToFileURL(createRequire(resolve(REPO, "signer/package.json")).resolve("starknet")).href);

const TARGET = resolve(REPO, "contracts/target/dev");
const RPC = process.env.PQ_RPC || "https://api.zan.top/public/starknet-sepolia/rpc/v0_10";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const RELEASE = opt("--release") || "testnet-v1";
const MANIFEST = resolve(opt("--manifest") || resolve(REPO, `release/${RELEASE}.json`));

// testnet-v1: what the release contains. Compact and record exceed Sepolia's per-block L2 gas cap
// when declared (bench/pf04), so they are listed for their artifacts only.
const V1_CLASSES = {
  HybridShakeVerifierPfSmall: { role: "verifier", declarable: true },
  HybridShakeAccount: { role: "verifier", declarable: true },
  HybridPoseidonAccount: { role: "verifier", declarable: true },
  HybridMigratableAccount: { role: "account", declarable: true },
  VerifierSwitchGuard: { role: "guard", declarable: true },
  HybridShakeVerifierPfCompact: { role: "verifier", declarable: false },
  HybridShakeVerifierPfRecord: { role: "verifier", declarable: false },
};
// Declare transactions on record (bench/pf04/sepolia.json). The others were declared before
// receipts were kept; --chain confirms they are declared.
const V1_DECLARE_TX = {
  HybridShakeVerifierPfSmall: "0x18feecd71b354a738babe560822d471232d6ec6ff5b5097877bc458b3c0cd62",
  VerifierSwitchGuard: "0x687a8500c3732f619db3a0f8db15ae271a8391282cb52f91b0f3cab69169e23",
};
const V1_TOOLCHAIN = {
  scarb: "2.18.0", cairo: "2.18.0", sierra: "1.8.0", snforge: "0.59.0",
  universal_sierra_compiler: "2.10.3", starknet_js: "10.8.0", noble_post_quantum: "0.6.1",
};

const RELEASES = {
  "testnet-v1": {
    classes: V1_CLASSES,
    declareTx: V1_DECLARE_TX,
    toolchain: V1_TOOLCHAIN,
    patches: "vendor/provably-fast/falcon-512",
    note: "Experimental, unaudited, testnet only. Class hashes are Sepolia declarations; compact and record cannot be declared there.",
    source: { cairo_pq_verifiers: "bece5c07eeea5784e570c01108ec000d2d04ae40" },
    verifiers: {
      "shake-pf-small-v1": "HybridShakeVerifierPfSmall",
      "shake-baseline": "HybridShakeAccount",
      poseidon: "HybridPoseidonAccount",
    },
    // The unpatched OpenZeppelin verifier stays the default until a review covers the small
    // patch; PQ_VERIFIER=shake-pf-small-v1 selects the optimized one.
    default_verifier: "shake-baseline",
    guard: "0x5093253fe6ee74bce57ae826a72bc94ddf02b6fbe20db5512e744a9a304945e",
    legacy: true,
  },
  // PF-13: the scheme-switch account and ML-DSA-44, declared 2026-11-26 (bench/pf13/sepolia.json).
  // Sepolia declared only Sierra 1.10.0 that day, so this release is built with scarb 2.22.0.
  "testnet-v2": {
    classes: {
      HybridMigratableAccountV2: { role: "account", declarable: true },
      HybridMlDsa44Verifier: { role: "verifier", declarable: true },
      MlDsa44KeySetup: { role: "setup", declarable: true },
    },
    declareTx: {
      HybridMigratableAccountV2: "0x531e2875a033559659bcd9e82030c2a903aea90c7aa87529af97d2c5b2e43e3",
      HybridMlDsa44Verifier: "0x55b2e1cf3bb6962e1778f77c6fce731d77953a12f6bfa59ecdf44a24718514b",
      MlDsa44KeySetup: "0x65cbd374c750205134da3561e820eb62e71996c7fb0633b42d2b49dbe12b990",
    },
    toolchain: {
      scarb: "2.22.0", cairo: "2.22.0", sierra: "1.10.0", snforge: "0.64.1",
      universal_sierra_compiler: "2.11.0-rc.1", starknet_js: "10.8.0", noble_post_quantum: "0.6.1",
    },
    patches: "vendor/provably-fast/ml-dsa-44",
    note: "Experimental, unaudited, testnet only. Class hashes are Sepolia declarations. Falcon-512 verifiers stay in testnet-v1; a V2 account can use them.",
    // The lane's baseline bundle (vendor/provably-fast/ml-dsa-44/PROVENANCE.md); its parent is
    // the cairo-pq-verifiers commit testnet-v1 pins.
    source: { provably_fast_ml_dsa_44_bundle: "78c83599f57ecb28847ba3ebc4528598318129b8" },
    // Each verifier names its scheme and the setup class set_pq_key / migrate library-calls once.
    verifiers: {
      "ml-dsa-44": { class: "HybridMlDsa44Verifier", scheme: "ml-dsa-44", setup: "MlDsa44KeySetup" },
    },
    default_verifier: "ml-dsa-44",
  },
};
const REL = RELEASES[RELEASE];
if (!REL) { console.error(`unknown release ${RELEASE}; known: ${Object.keys(RELEASES).join(", ")}`); process.exit(2); }
const CLASSES = REL.classes;
const PATCHES = resolve(REPO, REL.patches);
// A verifier entry is a class name (testnet-v1) or { class, scheme, setup } (testnet-v2).
const verifierEntry = (v) => (typeof v === "string" ? { class: v } : v);

const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const artifact = (name, kind) => resolve(TARGET, `pq_hybrid_${name}.${kind}.json`);
const same = (a, b) => a != null && b != null && BigInt(a) === BigInt(b);

// Starknet 0.14.1 and later hash compiled classes with Blake2s; that is the hash a declare now signs.
function built(name) {
  const sierraPath = artifact(name, "contract_class");
  const casmPath = artifact(name, "compiled_contract_class");
  return {
    class_hash: hash.computeContractClassHash(JSON.parse(readFileSync(sierraPath, "utf8"))),
    compiled_class_hash: hash.computeCompiledClassHashBlake(JSON.parse(readFileSync(casmPath, "utf8"))),
    sierra_sha256: sha256(sierraPath),
    casm_sha256: sha256(casmPath),
  };
}

function patchSums() {
  const sums = {};
  for (const line of readFileSync(resolve(PATCHES, "SHA256SUMS"), "utf8").trim().split("\n")) {
    const [digest, file] = line.trim().split(/\s+/);
    if (sha256(resolve(PATCHES, file)) !== digest) throw new Error(`${file} does not match SHA256SUMS`);
    sums[file] = digest;
  }
  return sums;
}

function write() {
  let old = {};
  try { old = JSON.parse(readFileSync(MANIFEST, "utf8")); } catch {}
  const commit = flag("--commit") || !old.source?.commit
    ? execFileSync("git", ["rev-parse", "HEAD"], { cwd: REPO, encoding: "utf8" }).trim()
    : old.source.commit;
  const classes = {};
  for (const [name, meta] of Object.entries(CLASSES)) {
    classes[name] = {
      role: meta.role,
      ...built(name),
      declarable: meta.declarable,
      declare_tx: old.classes?.[name]?.declare_tx ?? REL.declareTx[name] ?? null,
    };
  }
  const manifest = {
    release: RELEASE,
    network: "SN_SEPOLIA",
    experimental: true,
    note: REL.note,
    source: { commit, ...REL.source, provably_fast_patches: patchSums() },
    toolchain: REL.toolchain,
    classes,
    verifiers: REL.verifiers,
    default_verifier: REL.default_verifier,
    ...(REL.guard && { guard_instance: old.guard_instance ?? REL.guard }),
    ...(REL.legacy && { legacy_account_classes: old.legacy_account_classes ?? {} }),
  };
  writeFileSync(MANIFEST, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`wrote ${MANIFEST} (${Object.keys(classes).length} classes, source ${commit.slice(0, 7)})`);
}

function check() {
  const m = JSON.parse(readFileSync(MANIFEST, "utf8"));
  const bad = [];
  const line = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) bad.push(what); };
  for (const name of Object.keys(CLASSES)) {
    const want = m.classes?.[name];
    if (!want) { line(false, `${name}: missing from the manifest`); continue; }
    const got = built(name);
    for (const field of ["class_hash", "compiled_class_hash"]) {
      line(same(want[field], got[field]), `${name} ${field} ${want[field] ?? "(missing)"}${same(want[field], got[field]) ? "" : ` != built ${got[field]}`}`);
    }
    for (const field of ["sierra_sha256", "casm_sha256"]) {
      line(want[field] === got[field], `${name} ${field} ${want[field] ?? "(missing)"}${want[field] === got[field] ? "" : ` != built ${got[field]}`}`);
    }
  }
  const sums = patchSums();
  const pinned = m.source?.provably_fast_patches ?? {};
  for (const file of new Set([...Object.keys(sums), ...Object.keys(pinned)])) {
    line(sums[file] === pinned[file], `patch ${file} ${pinned[file] ?? "(missing)"}${sums[file] === pinned[file] ? "" : ` != SHA256SUMS ${sums[file] ?? "(absent)"}`}`);
  }
  for (const [id, v] of Object.entries(m.verifiers ?? {})) {
    const e = verifierEntry(v);
    line(!!m.classes?.[e.class], `verifier ${id} -> ${e.class}`);
    if (e.setup) line(m.classes?.[e.setup]?.role === "setup", `verifier ${id} setup -> ${e.setup}`);
  }
  line(!!m.verifiers?.[m.default_verifier], `default verifier ${m.default_verifier}`);
  if (bad.length) { console.error(`\n${bad.length} mismatch(es) against ${MANIFEST}`); process.exit(1); }
  console.log(`\nmanifest matches the built artifacts and the pinned patches`);
}

// Public RPC endpoints rate-limit bursts; a transient failure must not read as a missing class.
async function retry(fn, tries = 6) {
  for (let i = 0; ; i++) {
    try { return await fn(); } catch (e) {
      const msg = String(e?.message || e);
      if (i + 1 >= tries || !/429|rate|limit|too many|fetch failed|ECONNRESET|timeout|503|502/i.test(msg)) throw e;
      await new Promise((r) => setTimeout(r, 2000 * (i + 1)));
    }
  }
}

async function chain() {
  const m = JSON.parse(readFileSync(MANIFEST, "utf8"));
  const provider = new RpcProvider({ nodeUrl: RPC });
  let bad = 0;
  for (const [name, c] of Object.entries(m.classes)) {
    if (!c.declarable) { console.log(`--   ${name}: not declarable (expected)`); continue; }
    try {
      await retry(() => provider.getClassByHash(c.class_hash));
      let tx = "";
      if (c.declare_tx) {
        const t = await retry(() => provider.getTransactionByHash(c.declare_tx));
        if (!same(t.class_hash, c.class_hash)) throw new Error(`declare_tx ${c.declare_tx} declared ${t.class_hash}`);
        if (!same(t.compiled_class_hash, c.compiled_class_hash)) throw new Error(`declare_tx ${c.declare_tx} signed compiled class ${t.compiled_class_hash}`);
        tx = `, declared by ${c.declare_tx.slice(0, 10)}…`;
      }
      console.log(`ok   ${name} ${c.class_hash} is declared${tx}`);
    } catch (e) {
      bad++;
      console.log(`FAIL ${name} ${c.class_hash}: ${e.message.split("\n")[0]}`);
    }
  }
  // Earlier HybridMigratableAccount builds that deployed accounts still run (not rebuildable from
  // this commit): each must be declared, and each listed account must still run it.
  if (REL.legacy && !m.legacy_account_classes) { bad++; console.log("FAIL legacy_account_classes: missing from the manifest"); }
  for (const [h, c] of Object.entries(m.legacy_account_classes ?? {})) {
    try {
      await retry(() => provider.getClassByHash(h));
      for (const a of c.accounts) {
        const runs = await retry(() => provider.getClassHashAt(a));
        if (!same(runs, h)) throw new Error(`${a} now runs ${runs}`);
      }
      console.log(`ok   legacy ${h} is declared; ${c.accounts.length} listed account(s) run it`);
    } catch (e) {
      bad++;
      console.log(`FAIL legacy ${h}: ${e.message.split("\n")[0]}`);
    }
  }
  if (REL.guard) {
    const guardClass = await retry(() => provider.getClassHashAt(m.guard_instance)).catch((e) => e.message);
    const ok = same(guardClass, m.classes.VerifierSwitchGuard.class_hash);
    if (!ok) bad++;
    console.log(`${ok ? "ok  " : "FAIL"} guard instance ${m.guard_instance} runs ${guardClass}`);
  }
  if (bad) process.exit(1);
}

if (flag("--write")) write();
else if (flag("--chain")) await chain();
else if (flag("--check")) check();
else { console.error("usage: release_manifest.mjs --check | --chain | --write [--commit] [--release NAME] [--manifest PATH]"); process.exit(2); }
