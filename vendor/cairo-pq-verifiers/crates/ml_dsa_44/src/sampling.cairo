//! ExpandA and SampleInBall (FIPS 204, Section 7.3).

use core::dict::Felt252Dict;
use crate::keccak::{SHAKE128_RATE, SHAKE256_RATE, absorb, keccak_f1600, squeeze};
use crate::ntt::Q;

const TAU: u32 = 39;

/// RejNTTPoly (Algorithm 30, with CoeffFromThreeBytes, Algorithm 14): a uniform NTT-domain
/// polynomial from SHAKE-128 of `seed`. The candidates are the output's 3-byte little-endian
/// integers with bit 23 dropped, kept when below q, read straight from the state: a block's 21
/// lanes are 7 runs of 3 lanes, 8 candidates each. Whole blocks are read, so the polynomial is
/// the first 256 kept.
pub fn rej_ntt_poly(seed: Span<u8>) -> Span<felt252> {
    let mut state = absorb(seed, SHAKE128_RATE);
    let mut a: Array<felt252> = array![];
    loop {
        let [
            l0,
            l1,
            l2,
            l3,
            l4,
            l5,
            l6,
            l7,
            l8,
            l9,
            l10,
            l11,
            l12,
            l13,
            l14,
            l15,
            l16,
            l17,
            l18,
            l19,
            l20,
            _,
            _,
            _,
            _,
        ] =
            state;
        candidates(l0, l1, l2, ref a);
        candidates(l3, l4, l5, ref a);
        candidates(l6, l7, l8, ref a);
        candidates(l9, l10, l11, ref a);
        candidates(l12, l13, l14, ref a);
        candidates(l15, l16, l17, ref a);
        candidates(l18, l19, l20, ref a);
        if a.len() >= 256 {
            break;
        }
        state = keccak_f1600(state);
    }
    a.span().slice(0, 256)
}

const TWO8: NonZero<u128> = 0x100;
const TWO16: NonZero<u128> = 0x10000;
const TWO24: NonZero<u128> = 0x1000000;

/// The 8 candidates in 3 consecutive lanes (24 bytes, bits 24k to 24k + 23 for candidate k).
#[inline(always)]
fn candidates(l0: u128, l1: u128, l2: u128, ref a: Array<felt252>) {
    let (x, c0) = DivRem::div_rem(l0, TWO24);
    let (c2_low, c1) = DivRem::div_rem(x, TWO24);
    let (x, c2_high) = DivRem::div_rem(l1, TWO8);
    let (x, c3) = DivRem::div_rem(x, TWO24);
    let (c5_low, c4) = DivRem::div_rem(x, TWO24);
    let (x, c5_high) = DivRem::div_rem(l2, TWO16);
    let (c7, c6) = DivRem::div_rem(x, TWO24);
    keep(c0, ref a);
    keep(c1, ref a);
    keep(c2_low + c2_high * 0x10000, ref a);
    keep(c3, ref a);
    keep(c4, ref a);
    keep(c5_low + c5_high * 0x100, ref a);
    keep(c6, ref a);
    keep(c7, ref a);
}

/// A candidate with bit 23 dropped (CoeffFromThreeBytes), kept when below q.
#[inline(always)]
fn keep(candidate: u128, ref a: Array<felt252>) {
    let coeff = candidate & 0x7fffff;
    if coeff < Q.into() {
        a.append(coeff.into());
    }
}

/// ExpandA (Algorithm 32): A_hat[r][s] = RejNTTPoly(rho || s || r), at index 4 * r + s.
pub fn expand_a(rho: Span<u8>) -> Array<Span<felt252>> {
    let mut out: Array<Span<felt252>> = array![];
    let mut r: u8 = 0;
    while r != 4 {
        let mut s: u8 = 0;
        while s != 4 {
            let mut seed: Array<u8> = array![];
            seed.append_span(rho);
            seed.append(s);
            seed.append(r);
            out.append(rej_ntt_poly(seed.span()));
            s += 1;
        }
        r += 1;
    }
    out
}

/// The next byte of SHAKE-256 output, squeezing the next block when this one runs out.
fn next_byte(ref bytes: Span<u8>, ref state: [u128; 25]) -> u32 {
    if bytes.is_empty() {
        state = keccak_f1600(state);
        bytes = squeeze(state, SHAKE256_RATE / 8).span();
    }
    (*bytes.pop_front().unwrap()).into()
}

/// SampleInBall (Algorithm 29) from c_tilde: TAU coefficients of +-1, as values mod q. The first
/// 8 bytes of SHAKE-256(c_tilde) are the signs, least significant bit first.
pub fn sample_in_ball(c_tilde: Span<u8>) -> Array<felt252> {
    let mut state = absorb(c_tilde, SHAKE256_RATE);
    let mut bytes = squeeze(state, SHAKE256_RATE / 8).span();
    let mut signs: u128 = 0;
    let mut scale: u128 = 1;
    let mut k = 0;
    while k != 8 {
        signs += next_byte(ref bytes, ref state).into() * scale;
        scale *= 256;
        k += 1;
    }
    let two: NonZero<u128> = 2_u128.try_into().unwrap();
    // 0 is a zero coefficient, 1 is +1 and 2 is -1.
    let mut c: Felt252Dict<u8> = Default::default();
    let mut i: u32 = 256 - TAU;
    while i != 256 {
        let mut j = next_byte(ref bytes, ref state);
        while j > i {
            j = next_byte(ref bytes, ref state);
        }
        let (rest, sign) = DivRem::div_rem(signs, two);
        signs = rest;
        let moved = c.get(j.into());
        c.insert(i.into(), moved);
        c.insert(j.into(), if sign == 0 {
            1
        } else {
            2
        });
        i += 1;
    }
    let mut out: Array<felt252> = array![];
    let mut n: u32 = 0;
    while n != 256 {
        let v = c.get(n.into());
        out.append(if v == 0 {
            0
        } else if v == 1 {
            1
        } else {
            Q.into() - 1
        });
        n += 1;
    }
    out
}
