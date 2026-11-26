//! Bit packing (FIPS 204, Section 7.1): t1 and z from their bytes, the hint's validity and its
//! positions, UseHint, and w1Encode.

use crate::ntt::Q;

const GAMMA1: u32 = 131072;
const GAMMA2: u32 = 95232;
/// (q - 1) / (2 * GAMMA2): w1's coefficients are in [0, 44).
const W1_MOD: u32 = 44;
const OMEGA: u32 = 80;
const TWO_POW_D: u32 = 8192;

/// t1[i] * 2^d (pkDecode, Algorithm 23): `bytes` are t1[i]'s 320 bytes, 10 bits a coefficient.
/// t1 < 2^10, so t1 * 2^13 <= q - 1 needs no reduction.
pub fn t1_scaled(bytes: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut at = 0;
    while at != 320 {
        let b0: u32 = (*bytes.at(at)).into();
        let b1: u32 = (*bytes.at(at + 1)).into();
        let b2: u32 = (*bytes.at(at + 2)).into();
        let b3: u32 = (*bytes.at(at + 3)).into();
        let b4: u32 = (*bytes.at(at + 4)).into();
        out.append(((b0 + 256 * (b1 % 4)) * TWO_POW_D).into());
        out.append(((b1 / 4 + 64 * (b2 % 16)) * TWO_POW_D).into());
        out.append(((b2 / 16 + 16 * (b3 % 64)) * TWO_POW_D).into());
        out.append(((b3 / 64 + 4 * b4) * TWO_POW_D).into());
        at += 5;
    }
    out
}

/// z[i] mod q (sigDecode, Algorithm 27, BitUnpack with a = GAMMA1 - 1, b = GAMMA1): `bytes` are
/// z[i]'s 576 bytes, 18 bits x a coefficient, z = GAMMA1 - x. None when ||z||inf >= GAMMA1 - BETA,
/// which is x <= 78 or x >= 262066.
pub fn z_unpack(bytes: Span<u8>) -> Option<Array<felt252>> {
    let mut out: Array<felt252> = array![];
    let mut at = 0;
    let mut short = true;
    while at != 576 {
        let b2: u32 = (*bytes.at(at + 2)).into();
        let b4: u32 = (*bytes.at(at + 4)).into();
        let b6: u32 = (*bytes.at(at + 6)).into();
        let x0 = (*bytes.at(at)).into() + 256 * (*bytes.at(at + 1)).into() + 65536 * (b2 % 4);
        let x1 = b2 / 4 + 64 * (*bytes.at(at + 3)).into() + 16384 * (b4 % 16);
        let x2 = b4 / 16 + 16 * (*bytes.at(at + 5)).into() + 4096 * (b6 % 64);
        let x3 = b6 / 64 + 4 * (*bytes.at(at + 7)).into() + 1024 * (*bytes.at(at + 8)).into();
        for x in array![x0, x1, x2, x3] {
            if x <= 78 || x >= 262066 {
                short = false;
            }
            let z = if x <= GAMMA1 {
                GAMMA1 - x
            } else {
                Q + GAMMA1 - x
            };
            out.append(z.into());
        }
        if !short {
            break;
        }
        at += 9;
    }
    if short {
        Some(out)
    } else {
        None
    }
}

/// HintBitUnpack's validity (Algorithm 21) on the hint's 84 bytes: per polynomial, its count
/// y[OMEGA + i] never falls and stays within OMEGA, its positions strictly increase, and every
/// byte after the last position is zero.
pub fn hint_valid(y: Span<u8>) -> bool {
    let mut index: u32 = 0;
    let mut valid = true;
    let mut i = 0;
    while i != 4 {
        let end: u32 = (*y.at(OMEGA + i)).into();
        if end < index || end > OMEGA {
            valid = false;
            break;
        }
        let first = index;
        while index != end {
            if index > first && *y.at(index - 1) >= *y.at(index) {
                valid = false;
                break;
            }
            index += 1;
        }
        if !valid {
            break;
        }
        i += 1;
    }
    while valid && index != OMEGA {
        if *y.at(index) != 0 {
            valid = false;
        }
        index += 1;
    }
    valid
}

/// UseHint (Algorithm 40, with Decompose, Algorithm 36) on every coefficient of one polynomial in
/// [0, q); `positions` are its hinted coefficients, strictly increasing.
pub fn use_hints(w: Span<felt252>, positions: Span<u8>) -> Array<u32> {
    let mut out: Array<u32> = array![];
    let mut rest = positions;
    let mut next: u32 = match rest.pop_front() {
        Some(p) => (*p).into(),
        None => 256,
    };
    let mut n: u32 = 0;
    for r in w {
        let hint = n == next;
        if hint {
            next = match rest.pop_front() {
                Some(p) => (*p).into(),
                None => 256,
            };
        }
        out.append(use_hint(hint, (*r).try_into().unwrap()));
        n += 1;
    }
    out
}

/// r = r1 * 2 * GAMMA2 + r0 with r0 in (-GAMMA2, GAMMA2], except that r1 = 44 becomes r1 = 0 with
/// r0 - 1, which is negative; a hint moves r1 one step towards r0's sign, mod 44.
fn use_hint(hint: bool, r: u32) -> u32 {
    let (quotient, rem) = DivRem::div_rem(r, (2 * GAMMA2).try_into().unwrap());
    let negative = rem > GAMMA2;
    let r1 = if negative {
        quotient + 1
    } else {
        quotient
    };
    if r1 == W1_MOD {
        return if hint {
            W1_MOD - 1
        } else {
            0
        };
    }
    if !hint {
        r1
    } else if !negative && rem != 0 {
        (r1 + 1) % W1_MOD
    } else {
        (r1 + W1_MOD - 1) % W1_MOD
    }
}

/// w1Encode for one polynomial (Algorithm 28): 6 bits a coefficient, appended to `out`.
pub fn w1_encode(w1: Span<u32>, ref out: Array<u8>) {
    let mut at = 0;
    while at != 256 {
        let c0 = *w1.at(at);
        let c1 = *w1.at(at + 1);
        let c2 = *w1.at(at + 2);
        let c3 = *w1.at(at + 3);
        out.append((c0 + 64 * (c1 % 4)).try_into().unwrap());
        out.append((c1 / 4 + 16 * (c2 % 16)).try_into().unwrap());
        out.append((c2 / 16 + 4 * c3).try_into().unwrap());
        at += 4;
    }
}
