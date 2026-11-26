#!/usr/bin/env python3
"""Generate the PF-13 ML-DSA-44 differential vectors, each with the reference verifier's verdict.

The lane's reference verifier (mldsa44.py, pinned by SHA-256 below) is the authority: every
vector's `expected` and `reason` are what its `verify_felts` answers. Sources:

  felts     the baseline crate's 70 felt tests (tests/felts.cairo: dilithium-py keys, valid,
            tampered, malformed encodings, hints and norms), re-judged by the reference;
  noble     bench/pf13/vectors.json (@noble/post-quantum through signer/mldsa_adapter.mjs);
  python    signatures made here from FIPS 204's signing equations (any y works, the reference
            judges the result): the largest valid |z| (130,993) and the most hints (80).

Categories: valid, edge (|z| and hint-count bounds, both sides), malformed (every HintBitUnpack
refusal, bits above a felt's bytes, wrong lengths), tampered (message, c-tilde, z, hints, key).

Usage: python3 -I bench/pf13/correctness/gen_vectors.py --reference PATH/mldsa44.py [--seed 1]
       about a minute (pure-Python signing grinds for the two edge signatures).
"""

import argparse
import hashlib
import importlib.util
import json
import random
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
REFERENCE_URL = "https://postquantum.provably.fast/reference/mldsa44.py"
REFERENCE_SHA256 = "02c79ee38eab5bb89c451ead196eb481ba80e9115ec73554a1f437f0fb4c56d8"
FELTS = REPO / "vendor/cairo-pq-verifiers/crates/ml_dsa_44/tests/felts.cairo"
NOBLE = HERE.parent / "vectors.json"


def load_reference(path: Path):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != REFERENCE_SHA256:
        raise SystemExit(f"{path}: SHA-256 {digest}, expected {REFERENCE_SHA256}")
    spec = importlib.util.spec_from_file_location("mldsa44_reference", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod  # its dataclass needs the module registered
    spec.loader.exec_module(mod)
    return mod


def baseline_felt_tests() -> list[tuple[str, int, list[int], list[int]]]:
    """(test name, message, pk, sig) for each test in the baseline crate's felts.cairo."""
    out = []
    for name, body in re.findall(r"fn (\w+)\(\) \{(.*?)\n\}", FELTS.read_text(), re.S):
        pk = re.search(r"let pk = array!\[(.*?)\];", body, re.S).group(1)
        sig = re.search(r"let sig = array!\[(.*?)\];", body, re.S).group(1)
        msg = re.search(r"verify\((0x[0-9a-f]+),", body).group(1)
        out.append((name, int(msg, 16), [int(x, 16) for x in re.findall(r"0x[0-9a-f]+", pk)],
                    [int(x, 16) for x in re.findall(r"0x[0-9a-f]+", sig)]))
    return out


class Signer:
    """ML-DSA-44 signing (FIPS 204 Algorithm 7) over the reference's primitives, with y from a
    seeded PRNG. Secrets s1, s2 are uniform in [-ETA, ETA]; only the public key is ever judged."""

    def __init__(self, ref, rng: random.Random):
        self.ref, self.rng = ref, rng
        r, q, n = ref, ref.Q, ref.N
        rho = rng.randbytes(32)
        self.a_hat = r.expand_a(rho)
        s1 = [[rng.randint(-r.ETA, r.ETA) for _ in range(n)] for _ in range(r.L)]
        s2 = [[rng.randint(-r.ETA, r.ETA) for _ in range(n)] for _ in range(r.K)]
        self.s1_hat = [r.ntt([x % q for x in p]) for p in s1]
        self.s2_hat = [r.ntt([x % q for x in p]) for p in s2]
        t = [[(x + e) % q for x, e in zip(self.mat(self.s1_hat)[i], s2[i])] for i in range(r.K)]
        t1, self.t0 = [], []
        for poly in t:
            lo = [((x + (1 << (r.D - 1)) - 1) % (1 << r.D)) - ((1 << (r.D - 1)) - 1) for x in poly]
            t1.append([(x - l) >> r.D for x, l in zip(poly, lo)])
            self.t0.append(lo)
        self.t0_hat = [r.ntt([x % q for x in p]) for p in self.t0]
        bits = "".join(f"{c:010b}"[::-1] for poly in t1 for c in poly)
        self.pk = rho + int(bits[::-1], 2).to_bytes(320 * r.K, "little")
        self.tr = r.H(self.pk, 64)

    def mat(self, v_hat):
        r = self.ref
        return [r.intt([sum(a * b for a, b in zip(col, row)) % r.Q
                        for col, row in zip(zip(*self.a_hat[i]), zip(*v_hat))]) for i in range(r.K)]

    def times_c(self, c_hat, v_hat):
        r = self.ref
        return [[centered(x, r.Q) for x in r.intt([a * b % r.Q for a, b in zip(c_hat, p)])] for p in v_hat]

    def attempt(self, message: int):
        """One iteration of the signing loop: (signature bytes, max |z|, hint count) or None."""
        r, q = self.ref, self.ref.Q
        mu = r.H(self.tr + b"\0\0" + r.message_bytes(message), 64)
        y = [[self.rng.randint(-r.GAMMA1 + 1, r.GAMMA1) for _ in range(r.N)] for _ in range(r.L)]
        w = self.mat([r.ntt([x % q for x in p]) for p in y])
        w1 = [[r.decompose(x)[0] for x in p] for p in w]
        c_tilde = r.H(mu + r.w1_encode(w1), r.C_TILDE_BYTES)
        c_hat = r.ntt([x % q for x in r.sample_in_ball(c_tilde)])
        cs1, cs2, ct0 = (self.times_c(c_hat, v) for v in (self.s1_hat, self.s2_hat, self.t0_hat))
        z = [[a + b for a, b in zip(yp, cp)] for yp, cp in zip(y, cs1)]
        zmax = max(abs(x) for p in z for x in p)
        if zmax >= r.GAMMA1 - r.BETA:
            return None
        r0 = [[r.decompose(wx - cx)[1] for wx, cx in zip(wp, cp)] for wp, cp in zip(w, cs2)]
        if max(abs(x) for p in r0 for x in p) >= r.GAMMA2 - r.BETA:
            return None
        if max(abs(x) for p in ct0 for x in p) >= r.GAMMA2:
            return None
        h = [[int(r.decompose(wx - c2 + c0)[0] != r.decompose(wx - c2)[0])
              for wx, c2, c0 in zip(wp, p2, p0)] for wp, p2, p0 in zip(w, cs2, ct0)]
        count = sum(map(sum, h))
        if count > r.OMEGA:
            return None
        positions, counts = [], []
        for poly in h:
            positions += [i for i, bit in enumerate(poly) if bit]
            counts.append(len(positions))
        hint = bytes(positions + [0] * (r.OMEGA - len(positions)) + counts)
        return c_tilde + r.z_bytes([x for p in z for x in p]) + hint, zmax, count


def centered(x: int, q: int) -> int:
    x %= q
    return x if x <= (q - 1) // 2 else x - q


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--out", type=Path, default=HERE / "vectors.json")
    args = p.parse_args()
    ref = load_reference(args.reference)
    rng = random.Random(args.seed)
    vectors = []

    def add(category, description, source, key, message, pk, sig):
        verdict = ref.verify_felts(message, pk, sig)
        vectors.append({"id": len(vectors), "category": category, "description": description,
                        "source": source, "key": key, "message": hex(message),
                        "public_key": [hex(x) for x in pk], "signature": [hex(x) for x in sig],
                        "expected": verdict.valid, "reason": verdict.reason})
        return verdict

    def felts(b: bytes) -> list[int]:
        return ref.pack_felts(b)

    # --- the baseline crate's felt tests -------------------------------------------------------
    for name, msg, pk, sig in baseline_felt_tests():
        kind = name.rsplit("_", 1)[0]
        category = ("valid" if kind.startswith("valid") else
                    "edge" if kind.startswith("z_") else
                    "malformed" if kind in {"key_high", "key_last", "sig_high", "sig_last", "sig_felt_max",
                                            "short_sig", "long_sig", "short_key", "long_key", "empty"}
                    or kind.startswith("hint") else "tampered")
        add(category, name, "baseline felts.cairo", f"dilithium-py-{name[-1]}", msg, pk, sig)

    # --- noble ----------------------------------------------------------------------------------
    noble = json.loads(NOBLE.read_text())
    for v in noble["vectors"]:
        pk = [int(x, 16) for x in v["public_key"]]
        sig = [int(x, 16) for x in v["signature"]]
        verdict = add("valid", f"noble vector {v['id']}", "noble", v["key"], int(v["message"], 16), pk, sig)
        if not verdict.valid:
            raise SystemExit(f"the reference rejects noble vector {v['id']}: {verdict.reason}")

    # Tampering on the first noble vector of each key, at the byte level.
    for v in noble["vectors"]:
        if v["message"] != "0x0":
            continue
        msg, pk = 0, ref.unpack_felts([int(x, 16) for x in v["public_key"]], ref.PK_BYTES)
        sig = ref.unpack_felts([int(x, 16) for x in v["signature"]], ref.SIG_BYTES)
        key = v["key"]

        def flip(b: bytes, i: int, mask: int = 1) -> bytes:
            return b[:i] + bytes([b[i] ^ mask]) + b[i + 1:]

        add("tampered", "message + 1", "noble", key, 1, felts(pk), felts(sig))
        add("tampered", "message p - 1", "noble", key, ref.FELT_PRIME - 1, felts(pk), felts(sig))
        add("tampered", "c-tilde bit 0", "noble", key, msg, felts(pk), felts(flip(sig, 0)))
        add("tampered", "c-tilde last byte", "noble", key, msg, felts(pk), felts(flip(sig, 31, 0x80)))
        z = ref.z_coefficients(sig)
        for i in (0, 511, 1023):
            z2 = z[:i] + [z[i] + 1 if z[i] < 1000 else z[i] - 1] + z[i + 1:]
            body = sig[:32] + ref.z_bytes(z2) + sig[32 + 2304:]
            add("tampered", f"z[{i}] moved by 1", "noble", key, msg, felts(pk), felts(body))
        hints = sig[-84:]
        add("tampered", "first hint position + 1", "noble", key, msg, felts(pk),
            felts(sig[:-84] + bytes([(hints[0] + 1) % 256]) + hints[1:]))
        add("tampered", "pk rho bit 0", "noble", key, msg, felts(flip(pk, 0)), felts(sig))
        add("tampered", "pk t1 last byte", "noble", key, msg, felts(flip(pk, ref.PK_BYTES - 1)), felts(sig))

    # --- python-signed edges --------------------------------------------------------------------
    signer = Signer(ref, rng)
    pk = felts(signer.pk)
    best_z = best_h = None
    attempts = 0
    while best_z is None or best_h is None or best_h[2] < ref.OMEGA:
        attempts += 1
        if attempts > 20000:
            break
        got = signer.attempt(0x5EED)
        if got is None:
            continue
        if best_z is None and got[1] == ref.GAMMA1 - ref.BETA - 1:
            best_z = got
        if best_h is None or got[2] > best_h[2]:
            best_h = got
    if best_z is None:
        raise SystemExit("no signature with |z| = 130,993 in 20,000 attempts")
    print(f"python signer: {attempts} attempts, most hints {best_h[2]}", file=sys.stderr)

    sig, _, hcount = best_z
    add("edge", "largest valid |z| (130,993)", "python", "python-0", 0x5EED, pk, felts(sig))
    z = ref.z_coefficients(sig)
    i = next(i for i, x in enumerate(z) if abs(x) == ref.GAMMA1 - ref.BETA - 1)
    z[i] += 1 if z[i] > 0 else -1
    add("edge", "|z| = 130,994 (the bound)", "python", "python-0", 0x5EED, pk,
        felts(sig[:32] + ref.z_bytes(z) + sig[32 + 2304:]))

    sig, _, hcount = best_h
    add("edge", f"most hints found ({hcount})", "python", "python-0", 0x5EED, pk, felts(sig))
    hints = bytearray(sig[-84:])
    n = hints[-1]  # total count: positions in hints[:n], cumulative counts in hints[80:84]
    counts = list(hints[80:])
    first_nonempty = next(k for k in range(4) if counts[k] > (counts[k - 1] if k else 0))

    def hinted(b: bytearray) -> list[int]:
        return felts(sig[:-84] + bytes(b))

    def mutate(desc: str, fn):
        b = bytearray(hints)
        fn(b)
        add("malformed", desc, "python", "python-0", 0x5EED, pk, hinted(b))

    mutate("hint count past 80", lambda b: b.__setitem__(83, 81))
    mutate("hint counts falling", lambda b: b.__setitem__(83, b[82] - 1))
    start = counts[first_nonempty - 1] if first_nonempty else 0
    if counts[first_nonempty] - start >= 2:
        mutate("hint positions repeated", lambda b: b.__setitem__(start + 1, b[start]))
        mutate("hint positions out of order",
               lambda b: (b.__setitem__(start, hints[start + 1]), b.__setitem__(start + 1, hints[start])))
    if n < ref.OMEGA:
        mutate("non-zero byte after the last hint", lambda b: b.__setitem__(ref.OMEGA - 1, 1))
    for felt, bit in ((0, 248), (77, 250), (78, 16)):
        s = list(felts(sig))
        s[felt] |= 1 << bit
        add("malformed", f"signature felt {felt} bit {bit} above its bytes", "python", "python-0", 0x5EED, pk, s)
    for nf in (0, 42, 44):
        add("malformed", f"public key of {nf} felts", "python", "python-0", 0x5EED, (pk + [0])[:nf], felts(sig))
    for nf in (0, 78, 80):
        add("malformed", f"signature of {nf} felts", "python", "python-0", 0x5EED, pk, (felts(sig) + [0])[:nf])

    args.out.write_text(json.dumps({
        "description": "PF-13 ML-DSA-44 differential vectors; `expected` is the reference verifier's verdict.",
        "seed": args.seed,
        "sources": ["vendor/cairo-pq-verifiers/crates/ml_dsa_44/tests/felts.cairo", noble["noble"],
                    "python signer in this file (FIPS 204 Algorithm 7, seeded y)"],
        "reference": REFERENCE_URL,
        "reference_sha256": REFERENCE_SHA256,
        "vectors": vectors,
    }, indent=1) + "\n")
    counts = {}
    for v in vectors:
        counts[(v["category"], v["expected"])] = counts.get((v["category"], v["expected"]), 0) + 1
    for (category, expected), n in sorted(counts.items()):
        print(f"{category:10} {'valid' if expected else 'invalid':8} {n}", file=sys.stderr)


if __name__ == "__main__":
    main()
