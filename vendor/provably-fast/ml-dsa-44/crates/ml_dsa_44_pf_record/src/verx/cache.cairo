//! The key's own work, done once (PF-13). tr and A-hat depend only on the public key, so the
//! account computes them when the key is set (`precompute`), stores them, and checks each signature
//! from them (`verify_cached`). Ported from provably.fast's `mldsa/account/cairo/cache.cairo`
//! (written for mj_eed20939) to this record's names. `verify_cached` is `super::tac` line for line
//! with ExpandA and tr replaced by the cached values. A child of `verx` so it can call `ead`.
use corelib_imports::bounded_int::{downcast, upcast};
use crate::sa0::Za;

pub const TR_FELTS: u32 = 8;
pub const A_FELTS: u32 = 410;

/// tr (eight 64-bit lanes) and A-hat (ten 24-bit coefficients to a felt) for a well-formed key.
pub fn precompute(pk: Span<felt252>) -> Option<(Array<felt252>, Array<felt252>)> {
    let lanes = crate::pk0::lah(pk)?;
    let (tr, a0, a1) = crate::x2::xai(lanes.span());
    let mut a_hat: Array<Span<Za>> = array![a0, a1];
    let mut ls = lanes.span();
    let [l0, l1, l2, l3] = (*ls.multi_pop_front::<4>().unwrap()).unbox();
    crate::x2::uab(l0, l1, l2, l3, 1, ref a_hat);
    let mut tr_felts: Array<felt252> = array![];
    for lane in tr {
        tr_felts.append(lane.into());
    }
    Some((tr_felts, pack_a(a_hat.span())))
}

/// `super::tac` with tr and A-hat taken from `precompute(pk)` instead of recomputed.
pub fn verify_cached(
    mh: felt252, pk: Span<felt252>, sig: Span<felt252>, tr: Span<felt252>, a_packed: Span<felt252>,
) -> bool {
    if sig.len() != 79 || tr.len() != TR_FELTS || a_packed.len() != A_FELTS {
        return false;
    }
    let (z, b31, ha, hh) = match crate::zread::zab(sig) {
        Some(z) => z,
        None => { return false; },
    };
    let f0: u256 = (*sig.at(0)).into();
    let fh = match core::internal::bounded_int::constrain::<
        _,
        0x1000000000000000000000000000000,
        crate::pk0::th::C<
            _, 0x1000000000000000000000000000000, 0xffffffffffffffffffffffffffffff,
            0xffffffffffffffffffffffffffffffff,
        >,
    >(f0.high) {
        Ok(v) => v,
        Err(_) => { return false; },
    };
    let hb = crate::pk0::kaa::<_, _, 0, 0xff000000000000000000000000000000>(b31, super::Uy);
    let ctv = u256 {
        low: f0.low,
        high: upcast(crate::pk0::gaa::<_, _, 0, 0xffffffffffffffffffffffffffffffff>(fh, hb)),
    };
    let tail = match crate::pk0::kac(ha, hh, sig) {
        Some(b) => b,
        None => { return false; },
    };
    let hint = tail.span();
    let lanes = match crate::pk0::lah(pk) {
        Some(l) => l,
        None => { return false; },
    };
    let he = match crate::pk0::dac(hint) {
        Some(c) => c,
        None => { return false; },
    };
    let mut tr_lanes: Array<u128> = array![];
    for t in tr {
        tr_lanes.append((*t).try_into().unwrap());
    }
    let a_hat = unpack_a(a_packed);
    let (c0, c1) = crate::x2::maa(ctv.low, 0x10000000000000000);
    let (c2, c3) = crate::x2::maa(ctv.high, 0x10000000000000000);
    let (muw, pab) = crate::x2::cai(tr_lanes.span(), super::bai(mh), [c0, c1, c2, c3]);
    let f = crate::pk0::cac(lanes.span());
    super::ead(hint, he, z.span(), a_hat.span(), f.span(), muw, ctv, pab.span())
}

fn pack_a(a_hat: Span<Span<Za>>) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut acc: felt252 = 0;
    let mut scale: felt252 = 1;
    let mut n: u32 = 0;
    for row in a_hat {
        for c in *row {
            let v: felt252 = upcast(*c);
            acc += v * scale;
            scale *= 0x1000000;
            n += 1;
            if n == 10 {
                out.append(acc);
                acc = 0;
                scale = 1;
                n = 0;
            }
        }
    }
    if n != 0 {
        out.append(acc);
    }
    out
}

fn unpack_a(packed: Span<felt252>) -> Array<Span<Za>> {
    let mut flat: Array<Za> = array![];
    for f in packed {
        // 240 bits: the low 120 hold five coefficients, the next 120 the other five.
        let v: u256 = (*f).into();
        let (top, low) = DivRem::div_rem(v.low, B120);
        five(low, ref flat);
        five(v.high * 0x100 + top, ref flat);
    }
    let all = flat.span();
    let mut rows: Array<Span<Za>> = array![];
    let mut i = 0;
    while i != 16 {
        rows.append(all.slice(256 * i, 256));
        i += 1;
    }
    rows
}

const B120: NonZero<u128> = 0x1000000000000000000000000000000;
const B24: NonZero<u128> = 0x1000000;

#[inline(always)]
fn five(x: u128, ref out: Array<Za>) {
    let (x, c) = DivRem::div_rem(x, B24);
    out.append(downcast(c).unwrap());
    let (x, c) = DivRem::div_rem(x, B24);
    out.append(downcast(c).unwrap());
    let (x, c) = DivRem::div_rem(x, B24);
    out.append(downcast(c).unwrap());
    let (x, c) = DivRem::div_rem(x, B24);
    out.append(downcast(c).unwrap());
    out.append(downcast(x).unwrap());
}
