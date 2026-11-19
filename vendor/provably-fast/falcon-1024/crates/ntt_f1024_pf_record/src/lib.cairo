//! Modular Number-Theoretic Transform (NTT) for Starknet.
//!
//! A reusable, scheme-agnostic NTT engine optimized for the Cairo cost model: butterfly
//! arithmetic runs natively in `felt252` (one field multiplication and a few additions per
//! butterfly, no per-operation modular reduction), and reduction happens in at most two
//! u128 passes per transform — [`engine::ntt_lazy`] skips the forward transform's final
//! pass entirely and reports the exact output bound instead. See `engine` for the
//! algorithm and its safety argument, which is additionally proven executable by
//! `scripts/gen_ntt_tables.py`.
//!
//! Parameter sets plug in through [`engine::NttConfig`]: a modulus, root tables, and a
//! leaf permutation. [`falcon512`] provides the Falcon-512 set (q = 12289, n = 512,
//! tprest/falcon.py interop convention — the same transform s2morrow uses); other
//! lattice schemes (Falcon-1024, ML-DSA) can define their own config without touching
//! the engine. [`falcon512_fast::ntt_falcon512_fast_unchecked`] is the generated,
//! fixed-parameter forward path for callers that already hold canonical Falcon-512
//! coefficients. Its name makes the unchecked `[0, q)` input precondition explicit.

pub mod bitrev;
pub mod engine;
pub mod falcon512;
pub mod falcon512_fast;
pub mod roots;
pub mod roots_felt;
pub mod roots_scaled;

pub use engine::{NttConfig, intt, ntt, ntt_lazy, reduce_felt};
pub use falcon512_fast::{ntt_falcon512_fast_u16_unchecked, ntt_falcon512_fast_unchecked};
pub mod ci{pub use corelib_imports::bounded_int;pub use corelib_imports::integer; }
pub mod typed_ntt;
/// One typed NTT output word.
#[derive(Copy, Drop)]
pub struct I {
    pub v: typed_ntt::RawIn,
}

/// Six triples of typed NTT outputs (18 coordinates).
#[derive(Copy, Drop)]
pub struct G {
    pub g: [[W; 3]; 6],
}

/// Three twiddle roots of the merge check (one trio).
#[derive(Copy, Drop)]
pub struct R {
    pub a: u16,
    pub b: u16,
    pub c: u16,
}

/// Six root triples: the 18 roots of one merge-check group.
#[derive(Copy, Drop)]
pub struct S {
    pub s0: u16,
    pub s1: u16,
    pub s2: u16,
    pub s3: u16,
    pub s4: u16,
    pub s5: u16,
    pub s6: u16,
    pub s7: u16,
    pub s8: u16,
    pub s9: u16,
    pub s10: u16,
    pub s11: u16,
    pub s12: u16,
    pub s13: u16,
    pub s14: u16,
    pub s15: u16,
    pub s16: u16,
    pub s17: u16,
}

/// Four groups: the 72 roots one merge-check iteration reads.
#[derive(Copy, Drop)]
pub struct Q {
    pub a: S,
    pub b: S,
    pub c: S,
    pub d: S,
}

/// 2 consecutive typed NTT inputs of one half.
#[derive(Copy, Drop)]
pub struct J {
    pub a: I,
    pub b: I,
}

/// Four output groups of one half: the element merge_check pops per iteration.
#[derive(Copy, Drop)]
pub struct F {
    pub a: G,
    pub b: G,
    pub c: G,
    pub d: G,
}

#[derive(Copy, Drop)]
pub struct W {
    pub v: typed_ntt::Wv,
}
