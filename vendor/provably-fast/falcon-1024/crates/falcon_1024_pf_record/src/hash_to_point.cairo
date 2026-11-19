//! The standard SHAKE-256 hash-to-point of the Falcon specification at n = 1024, as OpenZeppelin's
//! Falcon-512 crate drives it (hash_to_point_shake_512): absorb salt || message hash, then read the
//! squeezed stream as big-endian 16-bit words, keeping word % q while word < 5q, until 1024
//! coefficients. The salt is two 20-byte little-endian felts and the message hash its 32
//! little-endian bytes; the 72-byte input fits one rate block, assembled straight into lanes.

use crate::keccak::keccak_f1600;

const N: u32 = 1024;
const REJECT_BOUND: u32 = 61445;

#[inline(always)]
pub fn hash_to_point(
    message_hash: felt252, salt_a: felt252, salt_b: felt252,
) -> Option<Array<Acc5>> {
    let (sah, sal) = match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(salt_a) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => { return hash_to_point_cold(message_hash, salt_a, salt_b); },
    };
    let (sbh, sbw) = match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(salt_b) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => { return hash_to_point_cold(message_hash, salt_a, salt_b); },
    };
    let ha: T32 = match downcast(sah) {
        Some(v) => v,
        None => { return None; },
    };
    let hb: T32 = match downcast(sbh) {
        Some(v) => v,
        None => { return None; },
    };
    let (mhh, mhl) = match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(message_hash) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => { return hash_to_point_cold(message_hash, salt_a, salt_b); },
    };
    // The absorbed block as little-endian lanes: bytes 0..40 the salt, 40..72 the message hash,
    let (sb12, sbl) = bounded_int::div_rem(sbw, N96);
    let l23: u128 = upcast(bounded_int::add(ha, bounded_int::mul(sbl, U32S)));
    let l4: crate::fk::u = bounded_int::add(sb12, bounded_int::mul(hb, U32S));
    let kc = crate::fk::eo();
    let mut coeffs: Array<Acc5> = array![];
    let kb = crate::fk::kbox();
    let st = absorb(sal, mhl, l23, mhh, l4, kc, kb);
    let (m128, _, d, _, _) = hcells();
    first(st, ref coeffs, m128, d, 15, kc, SLOTB, kb);
    Some(coeffs)
}

#[inline(never)]
fn hash_to_point_cold(
    message_hash: felt252, salt_a: felt252, salt_b: felt252,
) -> Option<Array<Acc5>> {
    match core::gas::withdraw_gas() {
        Some(_) => {},
        None => { return None; },
    }
    let sa: u256 = salt_a.into();
    let sb: u256 = salt_b.into();
    let ha: T32 = match downcast(sa.high) {
        Some(v) => v,
        None => { return None; },
    };
    let hb: T32 = match downcast(sb.high) {
        Some(v) => v,
        None => { return None; },
    };
    let mh: u256 = message_hash.into();
    let (sb12, sbl) = bounded_int::div_rem(sb.low, N96);
    let l23: u128 = upcast(bounded_int::add(ha, bounded_int::mul(sbl, U32S)));
    let l4: crate::fk::u = bounded_int::add(sb12, bounded_int::mul(hb, U32S));
    let kc = crate::fk::eo();
    let mut coeffs: Array<Acc5> = array![];
    let kb = crate::fk::kbox();
    let p4: u64 = upcast(l4);
    let c4: crate::fk::u = upcast(p4 ^ 0x1f);
    let st = crate::fk::bbk(
        crate::fk::bJc(sa.low, mh.low, l23, mh.high, crate::fk::aa(l4, 0x1f), (crate::fk::QFc(sa.low ^ mh.low), l23 ^ mh.high, c4)),
        0, kb,
    );
    let (m128, _, d, _, _) = hcells();
    first(st, ref coeffs, m128, d, 15, kc, SLOTB, kb);
    Some(coeffs)
}

#[inline(never)]
fn first(
    st: ([u128; 10], crate::fk::bD), ref coeffs: Array<Acc5>, m128: u128, d: D16, n: felt252,
    kc: crate::fk::co, sb: u128, kb: Box<crate::fk::az>,
) {
    let n64 = kc.two64;
    blk7(st, m128, n64, d, sb, ref coeffs);
    let ([_, _, _, u3, _, _, _, _, _, _], _) = st;
    let (sh, c) = sw128p(u3, m128);
    let t = c & sb;
    if t == 0 {
        peel8(sh, n64, d, ref coeffs);
        if n != 0 {
            let m = n - 1;
            return first(crate::fk::knk(st, kc, kb), ref coeffs, m128, d, m, kc, sb, kb);
        }
        if !full(@coeffs) {
            let (mk, _, dk, _, _) = hcells();
            last(st, ref coeffs, mk, dk, kc, kb);
        }
        return;
    }
    let (h, l) = bounded_int::div_rem(sh, n64);
    x64(l, d, ref coeffs);
    match constrain::<u128, 0x10000000000000000>(t) {
        Ok(_) => peel4(h, d, ref coeffs),
        Err(_) => x64(h, d, ref coeffs),
    }
    if n != 0 { return first(crate::fk::knk(st, kc, kb), ref coeffs, m128, d, n - 1, kc, sb, kb); }
    if full(@coeffs) { return; }
    last(st, ref coeffs, m128, d, kc, kb);
}

#[inline(always)]
fn blk7(
    st: ([u128; 10], crate::fk::bD), m128: u128, n64: NonZero<UnitInt<0x10000000000000000>>, d: D16, sb: u128,
    ref coeffs: Array<Acc5>,
) {
    let ([u0, u1, u2, _, v0, v1, v2, _, bk, bl], _) = st;
    let (s9, s4) = bounded_int::div_rem(sw128(bk, m128), n64);
    let (_, l14) = bounded_int::div_rem(sw128(bl, m128), n64);
    c128(u0, m128, n64, d, sb, ref coeffs);
    c128(v0, m128, n64, d, sb, ref coeffs);
    x64(s4, d, ref coeffs);
    c128(u1, m128, n64, d, sb, ref coeffs);
    c128(v1, m128, n64, d, sb, ref coeffs);
    x64(s9, d, ref coeffs);
    c128(u2, m128, n64, d, sb, ref coeffs);
    c128(v2, m128, n64, d, sb, ref coeffs);
    x64(l14, d, ref coeffs);
}

#[inline(always)]
fn c128(w: u128, m128: u128, n64: NonZero<UnitInt<0x10000000000000000>>, d: D16, sb: u128, ref coeffs: Array<Acc5>) {
    let (sh, c) = sw128p(w, m128);
    let (h, l) = bounded_int::div_rem(sh, n64);
    let t = c & sb;
    if t == 0 {
        peel4(l, d, ref coeffs);
        peel4(h, d, ref coeffs);
    } else {
        x64(l, d, ref coeffs);
        match constrain::<u128, 0x10000000000000000>(t) {
            Ok(_) => peel4(h, d, ref coeffs),
            Err(_) => x64(h, d, ref coeffs),
        }
    }
}
impl CarryHi of ConstrainHelper<u128, 0x10000000000000000> {
    type LowT = T64;
    type HighT = BoundedInt<0x10000000000000000, 0xffffffffffffffffffffffffffffffff>;
}

/// keccak_pre for last's two arms, out of line.
#[inline(always)]
fn lpre(st: ([u128; 10], crate::fk::bD), kc: crate::fk::co) -> crate::fk::jf {
    crate::fk::keccak_pre(st, kc)
}
#[inline(never)]
fn last(st: ([u128; 10], crate::fk::bD), ref coeffs: Array<Acc5>, m128: u128, d: D16, kc: crate::fk::co, kb: Box<crate::fk::az>) {
    let n64 = kc.two64;
    let mut st = st;
    if near(@coeffs) {
        let p = lpre(st, kc);
        let (_, m64, _, _, _) = hcells();
        let ([f0, hi, oo, _, _, _, _, _, _, _], (b00, b01, b02, b03, _)) = crate::fk::bbk(p, m128.into(), kb);
        Rt128::rt(sw128(f0, m128), d, ref coeffs);
        if full(@coeffs) { return; }
        let (g0, b04) = crate::fk::row0v(hi, oo, b00, b02, b03, kc);
        Rt128::rt(sw128(g0, m128), d, ref coeffs);
        if full(@coeffs) { return; }
        r64(sw64(crate::fk::lane4(b00, b01, b04, kc), m64), d, ref coeffs);
        if full(@coeffs) { return; }
        let mm = m128 & m128;
        let mm = mm & m128;
        let mm = mm & m128;
        let mm = mm & m128;
        st = crate::fk::bbk(p, 0, kb);
        let ([_, u1, _, _, _, v1, _, _, bk, _], _) = st;
        let (s9, _) = bounded_int::div_rem(sw128(bk, mm), n64);
        Rt128::rt(sw128(u1, mm), d, ref coeffs);
        Rt128::rt(sw128(v1, mm), d, ref coeffs);
        Rt128::rt(pad64(s9), d, ref coeffs);
        return ltail(st, ref coeffs, mm, m128, d, kc, kb);
    }
    let p = lpre(st, kc);
    let (_, m64, _, _, _) = hcells();
    let ([f0, o0, dk, bk, g0, dj, e4, ee, fk, _], (cj, cq, _, _, _)) = crate::fk::bbk(p, crate::fk::mode1(), kb);
    Rt128::rt(sw128(f0, m128), d, ref coeffs);
    Rt128::rt(sw128(g0, m128), d, ref coeffs);
    r64(sw64(fk, m64), d, ref coeffs);
    if full(@coeffs) { return; }
    let (f1, g1, fl) = crate::fk::row1(o0, dk, bk, dj, e4, ee, cj, cq, kc);
    Rt128::rt(sw128(f1, m128), d, ref coeffs);
    if full(@coeffs) { return; }
    Rt128::rt(sw128(g1, m128), d, ref coeffs);
    if full(@coeffs) { return; }
    r64(sw64(fl, m64), d, ref coeffs);
    if full(@coeffs) { return; }
    st = crate::fk::bbk(p, 0, kb);
    ltail(st, ref coeffs, m128, m128, d, kc, kb);
}

/// Rows both arms of last read after its permutation.
#[inline(never)]
fn ltail(st: ([u128; 10], crate::fk::bD), ref coeffs: Array<Acc5>, m: u128, m128: u128, d: D16, kc: crate::fk::co, kb: Box<crate::fk::az>) {
    let n64 = kc.two64;
    let ([_, _, u2, u3, _, _, v2, _, _, bl], _) = st;
    let (_, l14) = bounded_int::div_rem(sw128(bl, m), n64);
    Rt128::rt(sw128(u2, m), d, ref coeffs);
    Rt128::rt(sw128(v2, m), d, ref coeffs);
    Rt128::rt(pad64(l14), d, ref coeffs);
    if rd(u3, m, d, ref coeffs) { return; }
    last(st, ref coeffs, m128, d, kc, kb);
}

#[inline(always)]
fn rd(w: u128, m128: u128, d: D16, ref coeffs: Array<Acc5>) -> bool {
    Rt128::rt(sw128(w, m128), d, ref coeffs);
    full(@coeffs)
}

#[inline(always)]
fn pad64(x: T64) -> u128 {
    upcast(bounded_int::add(x, HI64))
}
const HI64: UnitInt<0xffffffffffffffff0000000000000000> = 0xffffffffffffffff0000000000000000;
impl Pad64Add of pqbench_ntt_f1024_pf_record::ci::bounded_int::AddHelper<T64, UnitInt<0xffffffffffffffff0000000000000000>> {
    type Result = BoundedInt<0xffffffffffffffff0000000000000000, 0xffffffffffffffffffffffffffffffff>;
}

#[inline(never)]
fn r64(q: T64, d: D16, ref c: Array<Acc5>) {
    // linear keeps (cold on the fixtures): 4 constrains instead of Rd's 15-leaf tree
    let (q, w): (T48, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    let (q, w): (T32, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    let (q, w): (W16, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    keep(q, ref c);
}

#[inline(always)]
fn absorb(u0: u128, u1: u128, v0: u128, v1: u128, l4: crate::fk::u, kc: crate::fk::co, kb: Box<crate::fk::az>) -> ([u128; 10], crate::fk::bD) {
    let p4: u64 = upcast(l4);
    let c4: crate::fk::u = upcast(p4 ^ 0x1f);
    crate::fk::bbk(
        crate::fk::bJ(
            u0, u1, 0x80000000000000000000000000000000, v0, v1, crate::fk::aa(l4, 0x1f),
            (crate::fk::QF(u0 ^ u1), v0 ^ v1, c4), kc,
        ),
        0, kb,
    )
}

use pqbench_ntt_f1024_pf_record::ci::bounded_int::{BoundedInt, DivRemHelper, UnitInt, bounded_int, upcast};
use core::internal::bounded_int::{ConstrainHelper, constrain, downcast};

pub(crate) type W16 = BoundedInt<0, 0xffff>;
pub(crate) type Acc5 = u16;
type Acc = BoundedInt<0, 61444>;
type Zq = BoundedInt<0, 12288>;
impl Split16 of DivRemHelper<u128, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffffffffffffffffffffffff>;
    type RemT = W16;
}
impl Split16b of DivRemHelper<BoundedInt<0, 0xffffffffffffffffffffffffffff>, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffffffffffffffffffff>;
    type RemT = W16;
}
impl Split16c of DivRemHelper<BoundedInt<0, 0xffffffffffffffffffffffff>, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffffffffffffffff>;
    type RemT = W16;
}
impl Accept of ConstrainHelper<W16, 61445> {
    type LowT = Acc;
    type HighT = BoundedInt<61445, 0xffff>;
}
impl ModQ of DivRemHelper<Acc5, UnitInt<12289>> {
    type DivT = BoundedInt<0, 5>;
    type RemT = Zq;
}
impl Split16d of DivRemHelper<BoundedInt<0, 0xffffffffffffffffffff>, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffffffffffff>;
    type RemT = W16;
}
impl Split16e of DivRemHelper<BoundedInt<0, 0xffffffffffffffff>, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffffffff>;
    type RemT = W16;
}
impl Split16f of DivRemHelper<BoundedInt<0, 0xffffffffffff>, UnitInt<0x10000>> {
    type DivT = BoundedInt<0, 0xffffffff>;
    type RemT = W16;
}
impl Split16g of DivRemHelper<BoundedInt<0, 0xffffffff>, UnitInt<0x10000>> {
    type DivT = W16;
    type RemT = W16;
}
const N16: NonZero<UnitInt<0x10000>> = 0x10000;
const N64: NonZero<UnitInt<0x10000000000000000>> = 0x10000000000000000;
impl Split64 of DivRemHelper<u128, UnitInt<0x10000000000000000>> {
    type DivT = T64;
    type RemT = T64;
}
const NQ: NonZero<UnitInt<12289>> = 12289;
const INV256: felt252 = 0x7f8000000000010ef0000000000000000000000000000000000000000000001;


type T112 = BoundedInt<0, 0xffffffffffffffffffffffffffff>;
type T96 = BoundedInt<0, 0xffffffffffffffffffffffff>;
type T80 = BoundedInt<0, 0xffffffffffffffffffff>;
pub(crate) type T64 = BoundedInt<0, 0xffffffffffffffff>;
type T48 = BoundedInt<0, 0xffffffffffff>;
type T32 = BoundedInt<0, 0xffffffff>;
trait Rd<T> {
    fn run(q: T, d: D16, ref c: Array<Acc5>);
}
trait Rt<T> {
    fn rt(q: T, d: D16, ref c: Array<Acc5>);
}
impl RdW of Rd<W16> {
    #[inline(always)]
    fn run(q: W16, d: D16, ref c: Array<Acc5>) {
        if let Ok(a) = constrain::<W16, 61445>(q) {
            c.append(upcast(a));
        }
    }
}
impl RdG<
    T, impl H: DivRemHelper<T, UnitInt<0x10000>>, +Rd<H::DivT>, +Rt<H::DivT>, +Drop<H::DivT>,
    impl C: ConstrainHelper<H::RemT, 61445>, +Drop<C::HighT>,
> of Rd<T> {
    #[inline(always)]
    fn run(q: T, d: D16, ref c: Array<Acc5>) {
        let (q, w) = bounded_int::div_rem(q, d);
        match constrain::<H::RemT, 61445>(w) {
            Ok(a) => {
                c.append(upcast(a));
                Rd::run(q, d, ref c);
            },
            Err(_) => Rt::rt(q, d, ref c),
        }
    }
}
trait Pad<Tg> {
    fn pad(a: Acc) -> Acc5;
}
impl Pad0 of Pad<()> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61444>, Acc5>(upcast::<Acc, BoundedInt<0, 61444>>(a))
    }
}
impl Pad1 of Pad<((), u8)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61445>, Acc5>(upcast::<Acc, BoundedInt<0, 61445>>(a))
    }
}
impl Pad2 of Pad<((), u16)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61446>, Acc5>(upcast::<Acc, BoundedInt<0, 61446>>(a))
    }
}
impl Pad3 of Pad<(((), u16), u8)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61447>, Acc5>(upcast::<Acc, BoundedInt<0, 61447>>(a))
    }
}
impl Pad4 of Pad<((), u32)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61448>, Acc5>(upcast::<Acc, BoundedInt<0, 61448>>(a))
    }
}
impl Pad5 of Pad<(((), u32), u8)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61449>, Acc5>(upcast::<Acc, BoundedInt<0, 61449>>(a))
    }
}
impl Pad6 of Pad<(((), u32), u16)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61450>, Acc5>(upcast::<Acc, BoundedInt<0, 61450>>(a))
    }
}
impl Pad7 of Pad<((((), u32), u16), u8)> {
    #[inline(always)]
    fn pad(a: Acc) -> Acc5 {
        upcast::<BoundedInt<0, 61451>, Acc5>(upcast::<Acc, BoundedInt<0, 61451>>(a))
    }
}
#[inline(always)]
fn x64(q: T64, d: D16, ref c: Array<Acc5>) {
    let (q, w) = bounded_int::div_rem(q, d);
    match constrain::<W16, 61445>(w) {
        Ok(a) => {
            c.append(upcast(a));
            X48::<()>::run(q, d, ref c);
        },
        Err(_) => X48::<((), u32)>::run(q, d, ref c),
    }
}
trait X48<Tg> {
    fn run(q: T48, d: D16, ref c: Array<Acc5>);
}
impl X48I<Tg, +Pad<Tg>, +Pad<(Tg, u8)>, +Pad<(Tg, u16)>, +Pad<((Tg, u16), u8)>> of X48<Tg> {
    #[inline(always)]
    fn run(q: T48, d: D16, ref c: Array<Acc5>) {
        let (q, w) = bounded_int::div_rem(q, d);
        match constrain::<W16, 61445>(w) {
            Ok(a) => {
                c.append(upcast(a));
                X32::<Tg>::run(q, d, ref c);
            },
            Err(_) => X32::<(Tg, u16)>::run(q, d, ref c),
        }
    }
}
trait X32<Tg> {
    fn run(q: T32, d: D16, ref c: Array<Acc5>);
}
impl X32I<Tg, +Pad<Tg>, +Pad<(Tg, u8)>> of X32<Tg> {
    #[inline(always)]
    fn run(q: T32, d: D16, ref c: Array<Acc5>) {
        let (q, w) = bounded_int::div_rem(q, d);
        match constrain::<W16, 61445>(w) {
            Ok(a) => {
                c.append(upcast(a));
                XW::<Tg>::run(q, ref c);
            },
            Err(_) => XW::<(Tg, u8)>::run(q, ref c),
        }
    }
}
trait XW<Tg> {
    fn run(q: W16, ref c: Array<Acc5>);
}
impl XWI<Tg, +Pad<Tg>> of XW<Tg> {
    #[inline(always)]
    fn run(q: W16, ref c: Array<Acc5>) {
        if let Ok(a) = constrain::<W16, 61445>(q) {
            c.append(Pad::<Tg>::pad(a));
        }
    }
}
impl RtW of Rt<W16> {
    #[inline(always)]
    fn rt(q: W16, d: D16, ref c: Array<Acc5>) {
        RdW::run(q, d, ref c);
    }
}
impl Rt32 of Rt<T32> {
    #[inline(always)]
    fn rt(q: T32, d: D16, ref c: Array<Acc5>) {
        Rd::run(q, d, ref c);
    }
}
impl Rt48 of Rt<T48> {
    #[inline(always)]
    fn rt(q: T48, d: D16, ref c: Array<Acc5>) {
        Rd::run(q, d, ref c);
    }
}
impl Rt64 of Rt<T64> {
    #[inline(always)]
    fn rt(q: T64, d: D16, ref c: Array<Acc5>) {
        Rd::run(q, d, ref c);
    }
}
impl Rt80 of Rt<T80> {
    #[inline(always)]
    fn rt(q: T80, d: D16, ref c: Array<Acc5>) {
        let (q, w): (T64, W16) = bounded_int::div_rem(q, d);
        keep(w, ref c);
        r64(q, d, ref c);
    }
}
impl Rt96 of Rt<T96> {
    #[inline(always)]
    fn rt(q: T96, d: D16, ref c: Array<Acc5>) {
        let (q, w): (T80, W16) = bounded_int::div_rem(q, d);
        keep(w, ref c);
        Rt80::rt(q, d, ref c);
    }
}
impl Rt112 of Rt<T112> {
    #[inline(always)]
    fn rt(q: T112, d: D16, ref c: Array<Acc5>) {
        let (q, w): (T96, W16) = bounded_int::div_rem(q, d);
        keep(w, ref c);
        Rt96::rt(q, d, ref c);
    }
}
#[inline(always)]
fn keep(w: W16, ref c: Array<Acc5>) {
    if let Ok(a) = constrain::<W16, 61445>(w) {
        c.append(upcast(a));
    }
}
#[inline(always)]
fn sw128(w: u128, m: u128) -> u128 {
    let even = w & m;
    let ef: felt252 = even.into();
    let wf: felt252 = w.into();
    ((wf + ef * 65535) * INV256).try_into().unwrap()
}
#[inline(always)]
fn sw64(l: u128, m: u128) -> T64 {
    let even = l & m;
    let ef: felt252 = even.into();
    let lf: felt252 = l.into();
    core::internal::bounded_int::downcast((lf + ef * 65535) * INV256).unwrap()
}
impl Rt128 of Rt<u128> {
    #[inline(never)]
    fn rt(q: u128, d: D16, ref c: Array<Acc5>) {
        let (h, l) = bounded_int::div_rem(q, N64);
        k64(l, d, ref c);
        if full(@c) { core::gas::redeposit_gas(); return; }
        k64(h, d, ref c);
    }
}
#[inline(always)]
fn k64(q: T64, d: D16, ref c: Array<Acc5>) {
    let (q, w): (T48, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    let (q, w): (T32, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    let (q, w): (W16, W16) = bounded_int::div_rem(q, d);
    keep(w, ref c);
    keep(q, ref c);
}
type D16 = NonZero<UnitInt<0x10000>>;
#[inline(always)]
fn full(c: @Array<Acc5>) -> bool {
    match constrain::<u32, 1024>(c.len()) {
        Ok(_) => false,
        Err(_) => true,
    }
}
#[inline(always)]
fn near(c: @Array<Acc5>) -> bool {
    match constrain::<u32, 1008>(c.len()) {
        Ok(_) => false,
        Err(_) => true,
    }
}
impl LenN of ConstrainHelper<u32, 1024> {
    type LowT = BoundedInt<0, 1023>;
    type HighT = BoundedInt<1024, 0xffffffff>;
}
impl LenN16 of ConstrainHelper<u32, 1008> {
    type LowT = BoundedInt<0, 1007>;
    type HighT = BoundedInt<1008, 0xffffffff>;
}
type HK = (u128, u128, D16, NonZero<UnitInt<0x10000000000000000>>, u32);
#[inline(always)]
fn hcells() -> HK {
    (0x00ff00ff00ff00ff00ff00ff00ff00ff, 0x00ff00ff00ff00ff, N16, N64, N - 68)
}

const N96: NonZero<UnitInt<0x1000000000000000000000000>> = 0x1000000000000000000000000;
const U32S: UnitInt<0x100000000> = 0x100000000;
impl SaltSplit of DivRemHelper<u128, UnitInt<0x1000000000000000000000000>> {
    type DivT = T32;
    type RemT = T96;
}
impl SaltMul96 of pqbench_ntt_f1024_pf_record::ci::bounded_int::MulHelper<T96, UnitInt<0x100000000>> {
    type Result = BoundedInt<0, 0xffffffffffffffffffffffff00000000>;
}
impl SaltAdd96 of pqbench_ntt_f1024_pf_record::ci::bounded_int::AddHelper<T32, BoundedInt<0, 0xffffffffffffffffffffffff00000000>> {
    type Result = BoundedInt<0, 0xffffffffffffffffffffffffffffffff>;
}
impl SaltMul32 of pqbench_ntt_f1024_pf_record::ci::bounded_int::MulHelper<T32, UnitInt<0x100000000>> {
    type Result = BoundedInt<0, 0xffffffff00000000>;
}
impl SaltAdd32 of pqbench_ntt_f1024_pf_record::ci::bounded_int::AddHelper<T32, BoundedInt<0, 0xffffffff00000000>> {
    type Result = crate::fk::u;
}

const SLOT10: u128 = 0x00100010001000100010001000100010;
const SLOTB: u128 = 0x01000100010001000100010001000100;
#[inline(always)]
fn sw128c(w: u128, m: u128) -> (u128, bool) {
    let (s, c) = sw128p(w, m);
    (s, c & SLOTB == 0)
}
#[inline(always)]
fn sw128p(w: u128, m: u128) -> (u128, u128) {
    let even = w & m;
    let ef: felt252 = even.into();
    let wf: felt252 = w.into();
    let s: u128 = ((wf + ef * 65535) * INV256).try_into().unwrap();
    let c: Option<u128> = match constrain::<_, 0x100000000000000000000000000000000>(bounded_int::add(even, SLOT10)) { Ok(x) => Some(upcast(x)), Err(_) => None };
    (s, c.unwrap())
}
impl CA of pqbench_ntt_f1024_pf_record::ci::bounded_int::AddHelper<u128, u128> { type Result = BoundedInt<0, 0x1fffffffffffffffffffffffffffffffe>; }
impl CC of ConstrainHelper<BoundedInt<0, 0x1fffffffffffffffffffffffffffffffe>, 0x100000000000000000000000000000000> { type LowT = BoundedInt<0, 0xffffffffffffffffffffffffffffffff>; type HighT = BoundedInt<0x100000000000000000000000000000000, 0x1fffffffffffffffffffffffffffffffe>; }
#[inline(always)]
fn peel8(s: u128, n64: NonZero<UnitInt<0x10000000000000000>>, d: D16, ref c: Array<Acc5>) {
    let (h, l) = bounded_int::div_rem(s, n64);
    peel4(l, d, ref c);
    peel4(h, d, ref c);
}
#[inline(always)]
fn peel4(x: T64, d: D16, ref c: Array<Acc5>) {
    let (q, w) = bounded_int::div_rem(x, d);
    c.append(upcast(w));
    let (q, w) = bounded_int::div_rem(q, d);
    c.append(upcast(w));
    let (q, w) = bounded_int::div_rem(q, d);
    c.append(upcast(w));
    c.append(upcast(q));
}

#[cfg(test)]
mod fast_path_tests {
    use super::{Acc5, Rd, hcells, peel8, sw128c};
    use super::{bounded_int, upcast, Split64};
    fn fl(a: Array<Acc5>) -> Array<felt252> {
        let mut r: Array<felt252> = array![];
        for x in a { r.append(upcast(x)); }
        r
    }
    fn both(w: u128) -> (bool, Array<felt252>, Array<felt252>) {
        let (m128, _, d, n64, _) = hcells();
        let (s, k) = sw128c(w, m128);
        let mut a: Array<Acc5> = array![];
        let mut b: Array<Acc5> = array![];
        if k { peel8(s, n64, d, ref a); }
        let (h, l) = bounded_int::div_rem(s, n64);
        Rd::run(l, d, ref b);
        Rd::run(h, d, ref b);
        (k, fl(a), fl(b))
    }
    #[test]
    fn clean_word_matches_exact_reader() {
        let (k, a, b) = both(0xffef_00ef_1234_abcd_ef00_0001_7fee_80ef);
        assert!(k);
        assert!(a == b);
        assert!(a.len() == 8);
    }
    #[test]
    fn f0_slot_takes_exact_path() {
        let (k, _, b) = both(0x0000_0000_0000_0000_0000_04f0_0000_0000);
        assert!(!k);
        assert!(b.len() == 8);
        let (k2, _, b2) = both(0x0000_0000_0000_0000_0000_05f0_0000_0000);
        assert!(!k2);
        assert!(b2.len() == 7);
        let (k3, _, b3) = both(0xffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff);
        assert!(!k3);
        assert!(b3.len() == 0);
        let (k4, a4, b4) = both(0xffef_ffef_ffef_ffef_ffef_ffef_ffef_ffef);
        assert!(k4);
        assert!(a4 == b4);
    }
}

#[cfg(test)]
mod last_block_tests {
    use super::{hash_to_point, upcast};
    fn digest(m: felt252, sa: felt252, sb: felt252) -> (u32, felt252) {
        let c = hash_to_point(m, sa, sb).unwrap();
        let mut s: felt252 = 0;
        let mut i: felt252 = 1;
        for w in c.span().slice(0, 1024) {
            let x: felt252 = upcast(*w);
            s += i * x;
            i += 1;
        }
        (c.len(), s)
    }
    #[test]
    fn row0_fallback_reads_from_lane_5() {
        let (n, s) = digest(
            0x2c44149f61456dd8c294d70a39d4043e5339ee46e81794e3237a0f95958273f,
            0x9f52887de4f7a8048e09189ca27c7e7f548fce7b,
            0x9fe8241015742f0dd15609da1eb7b6b79c813e9e,
        );
        assert!(n >= 1024);
        assert!(s == 0x3ab91e729);
    }
    #[test]
    fn row0_completes_in_lane_4() {
        let (n, s) = digest(
            0x1151822737b6ed79182c3c8e288b16437d02410a675a109bdf84ab55632a446,
            0x703cff0b39763c0bd562ce04acc80ab55570e103,
            0x14777e962b56363cf5efd434db045aaecf4cc239,
        );
        assert!(n >= 1024);
        assert!(s == 0x3d4b6835b);
    }
}
