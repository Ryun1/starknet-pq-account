//! Base-q packing of 1024 coefficients into 57 felts, as the Falcon-512 season's layout packs 512
//! into 29: each felt is pack9(low) + 2^128 * pack9(high), base q with the first coefficient least
//! significant, and the last felt holds sixteen, nine low and seven high. Unpacking refuses any
//! half whose digits leave a remainder, so every key and signature has one encoding.

pub const SLOTS: u32 = 57;
const FULL_SLOTS: u32 = 56;

use pqbench_ntt_f1024_pf_record::J;
use pqbench_ntt_f1024_pf_record::ci::bounded_int::{BoundedInt,DivRemHelper,UnitInt,bounded_int,upcast};
use core::internal::bounded_int::{ConstrainHelper,constrain};
type Zq=BoundedInt<0,12288>;
type P1=BoundedInt<0,12288>;
type P2=BoundedInt<0,151019520>;
type P3=BoundedInt<0,1855878893568>;
type P4=BoundedInt<0,22806895723069440>;
type P5=BoundedInt<0,280273941540800360448>;
type P6=BoundedInt<0,3444286467594895629557760>;
type P7=BoundedInt<0,42326836400273672391635324928>;
type P8=BoundedInt<0,520154492522963160020806508052480>;
pub(crate) type P9=BoundedInt<0,6392178558614694273495691177456939008>;
impl D2 of DivRemHelper<P2,UnitInt<12289>> {type DivT=P1;type RemT=Zq; }
impl D3 of DivRemHelper<P3,UnitInt<12289>> {type DivT=P2;type RemT=Zq; }
impl D4 of DivRemHelper<P4,UnitInt<12289>> {type DivT=P3;type RemT=Zq; }
impl D5 of DivRemHelper<P5,UnitInt<12289>> {type DivT=P4;type RemT=Zq; }
impl D6 of DivRemHelper<P6,UnitInt<12289>> {type DivT=P5;type RemT=Zq; }
impl D7 of DivRemHelper<P7,UnitInt<12289>> {type DivT=P6;type RemT=Zq; }
impl D8 of DivRemHelper<P8,UnitInt<12289>> {type DivT=P7;type RemT=Zq; }
impl D9 of DivRemHelper<P9,UnitInt<12289>> {type DivT=P8;type RemT=Zq; }
impl C9 of ConstrainHelper<u128,6392178558614694273495691177456939009> {type LowT=P9;type HighT=BoundedInt<6392178558614694273495691177456939009,0xffffffffffffffffffffffffffffffff>; }
impl C7 of ConstrainHelper<u128,42326836400273672391635324929> {type LowT=P7;type HighT=BoundedInt<42326836400273672391635324929,0xffffffffffffffffffffffffffffffff>; }
const NQ:NonZero<UnitInt<12289>> =12289;


impl Center of ConstrainHelper<Zq,6145> {
type LowT=BoundedInt<0,6144>;
type HighT=BoundedInt<6145,12288>;
}
/// The square of the centered representative of a digit in [0, q) (one range check).
#[inline(always)]
fn sq(d:Zq) -> felt252{
match constrain::<Zq,6145>(d) {
Ok(lo) => {let x:felt252=upcast(lo);x*x},
Err(hi) => {let x:felt252=upcast(hi);let c=x-12289;c*c},
}
}

type T0=BoundedInt<18433,83968>;
type T1=BoundedInt<6145,83968>;
impl CdA of pqbench_ntt_f1024_pf_record::ci::bounded_int::AddHelper<crate::hash_to_point::Acc5,UnitInt<18433>> {type Result=T0; }
impl CdS of core::internal::bounded_int::SubHelper<T0,Zq> {type Result=T1; }
impl CdD of DivRemHelper<T1,UnitInt<12289>> {type DivT=BoundedInt<0,6>;type RemT=Zq; }
const U18433:UnitInt<18433> =18433;
/// p < 5q (unreduced message-point word), k in [0, q): the square of the centered representative
#[inline(always)]
fn cdiff(p:crate::hash_to_point::Acc5,k:Zq,nq:NonZero<UnitInt<12289>>) -> felt252{
let t:T1=bounded_int::sub(bounded_int::add(p,U18433),k);
let(_,r) =bounded_int::div_rem(t,nq);
let c:felt252=upcast::<Zq,felt252>(r) -6144;
c*c
}



use pqbench_ntt_f1024_pf_record::ci::bounded_int::{AddHelper,MulHelper};
use core::internal::bounded_int::SubHelper;
type N4D1=BoundedInt<0,422212465065984>;
type N4D2=BoundedInt<0,498460498419343452338927647605129216>;
type N4P2=BoundedInt<0,422212465078272>;
type N4P3=BoundedInt<0,498460498419343452339349860070207488>;
impl N4Mul1 of MulHelper<Zq,UnitInt<34359738368>> {type Result=N4D1; }
impl N4Mul2 of MulHelper<Zq,UnitInt<40564819207303340847894502572032>> {type Result=N4D2; }
impl N4Add1 of AddHelper<Zq,N4D1> {type Result=N4P2; }
impl N4Add2 of AddHelper<N4P2,N4D2> {type Result=N4P3; }
impl N4Bias3 of AddHelper<N4P3,UnitInt<83036184917349938715710381149390847>> {
type Result=BoundedInt<83036184917349938715710381149390847,581496683336693391055060241219598335>;
}
const N4B:UnitInt<34359738368> =34359738368;
const N4B3:UnitInt<40564819207303340847894502572032> =40564819207303340847894502572032;
const N4BIAS3:UnitInt<83036184917349938715710381149390847> =83036184917349938715710381149390847;
const N4MASK3:u128=332306998946228968226233240046804992;
const N4QINV:felt252=1808809682566871010753239355074989267886550786960801817186256343979052236802;
#[inline(always)]
fn sg3(d0:Zq,d1:Zq,d2:Zq,mk:u128) -> felt252{
let p:N4P3=bounded_int::add(bounded_int::add(d0,bounded_int::mul(d1,N4B)),bounded_int::mul(d2,N4B3));
let t:u128=upcast(bounded_int::add(p,N4BIAS3));
let flags=t & mk;
let v:felt252=upcast::<N4P3,felt252>(p) -flags.into() *N4QINV;
v*v
}
const OFJ:felt252=23945242826726411699303254272397162485873418786832384;
impl JU1 of DivRemHelper<u128,UnitInt<1180591620717411303423>> {
type DivT=BoundedInt<0,288230376151711744>;
type RemT=BoundedInt<0,1180591620717411303422>;
}
impl JU4 of DivRemHelper<u128,UnitInt<4835703278458516698824704>> {
type DivT=BoundedInt<0,70368744177663>;
type RemT=BoundedInt<0,4835703278458516698824703>;
}
const N70:NonZero<UnitInt<1180591620717411303423>> =1180591620717411303423;
const N82:NonZero<UnitInt<4835703278458516698824704>> =4835703278458516698824704;
/// Sum of the squares accumulated by sg3 and hq3: slots 0 and 70 (folded mod 2^70 - 1) and 210.
fn s1_packed_norm(cy:felt252) -> Option<SN> {
let(jh,jl) =match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(cy) {
pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => {return None; },
};
let(_,s02) =bounded_int::div_rem(jl & 40564819206122749227211451006975,N70);
let(s6,_) =bounded_int::div_rem(jh,N82);
Some(bounded_int::add(s02,s6))
}
/// A packed norm: slots 0 and 70 folded (below 2^70 - 1) plus slot 210 (below 2^46).
pub(crate) type SN=BoundedInt<0,1180591691086155481085>;
impl SnAdd of AddHelper<BoundedInt<0,1180591620717411303422>,BoundedInt<0,70368744177663>> {type Result=SN; }
pub(crate) impl SnBound of ConstrainHelper<SN,70265243> {type LowT=BoundedInt<0,70265242>;type HighT=BoundedInt<70265243,1180591691086155481085>; }
type HD1=BoundedInt<-12288,65535>;
type HB=BoundedInt<-422212465065984,2251765453946880>;
type HC=BoundedInt<-498460498419343452338927647605129216,2658415426750624442466766226058117120>;
type HAB=BoundedInt<-422212465078272,2251765454012415>;
type HABC=BoundedInt<-498460498419343452339349860070207488,2658415426750624442469017991512129535>;
type HX=BoundedInt<249270814028879029510522858897414145,3406146739198846924318890710479751168>;
type HW=BoundedInt<21188019192454717508394443006280202325,289522472831901988567105710390778849280>;
impl HqS of SubHelper<crate::hash_to_point::Acc5,Zq> {type Result=HD1; }
impl HqMb of MulHelper<HD1,UnitInt<34359738368>> {type Result=HB; }
impl HqMc of MulHelper<HD1,UnitInt<40564819207303340847894502572032>> {type Result=HC; }
impl HqAb of AddHelper<HD1,HB> {type Result=HAB; }
impl HqAc of AddHelper<HAB,HC> {type Result=HABC; }
impl HqC of AddHelper<HABC,UnitInt<747731312448222481849872718967621633>> {type Result=HX; }
impl HqW of MulHelper<HX,UnitInt<85>> {type Result=HW; }
const HPC:UnitInt<747731312448222481849872718967621633> =747731312448222481849872718967621633;
const HPMU:UnitInt<85> =85;
const HPE:felt252=249230249209671726169674930035103744;
const HPQ:felt252=3576095008238276593254811797070732988878109843115171765732780120446085365761;
const HPM:u128=297747071055821155530704983081937272832;
/// Three centered differences in slots 0, 35 and 105, squared. floor(85*x/2^20) is floor(x/q)
#[inline(always)]
fn hq3(ma:crate::hash_to_point::Acc5,ta:Zq,mb:crate::hash_to_point::Acc5,tb:Zq,mc:crate::hash_to_point::Acc5,tc:Zq,hm:u128) -> felt252{
let da:HD1=bounded_int::sub(ma,ta);
let db:HD1=bounded_int::sub(mb,tb);
let dc:HD1=bounded_int::sub(mc,tc);
let x:HX=bounded_int::add(bounded_int::add(bounded_int::add(da,bounded_int::mul(db,N4B)),bounded_int::mul(dc,N4B3)),HPC);
let w:u128=upcast(bounded_int::mul(x,HPMU));
let f=w & hm;
let y:felt252=upcast::<HX,felt252>(x) -HPE;
let v=y-f.into() *HPQ;
v*v
}

type HX2=BoundedInt<747731312448222481849450506502543361,747731312448222481852124484421634048>;
type HW2=BoundedInt<63557161558098910957203293052716185685,63557161558098910957430581175838894080>;
impl HqC2 of AddHelper<HAB,UnitInt<747731312448222481849872718967621633>> {type Result=HX2; }
impl HqW2 of MulHelper<HX2,UnitInt<85>> {type Result=HW2; }
/// hq3(ma, ta, b, 0, 0, 0, hm): the same value without the empty third lane's ops and the second
#[inline(always)]
fn hq2(ma:crate::hash_to_point::Acc5,ta:Zq,b:Zq,hm:u128) -> felt252{
let da:HD1=bounded_int::sub(ma,ta);
let db:HD1=upcast(b);
let x:HX2=bounded_int::add(bounded_int::add(da,bounded_int::mul(db,N4B)),HPC);
let w:u128=upcast(bounded_int::mul(x,HPMU));
let f=w & hm;
let y:felt252=upcast::<HX2,felt252>(x) -HPE;
let v=y-f.into() *HPQ;
v*v
}

/// Q50: a felt's halves, the high half below q^9.
const TWO128: felt252 = 0x100000000000000000000000000000000;
/// Zero, the high half of a felt below 2^128 (a narrow felt: its high digits are all zero).
const Z0:UnitInt<0> =0;
type P9e=BoundedInt<0,6392178558614694273495691177456939009>;
type P9o=BoundedInt<1,6392178558614694273495691177456939009>;
impl C9e of ConstrainHelper<u128,6392178558614694273495691177456939010> {type LowT=P9e;type HighT=BoundedInt<6392178558614694273495691177456939010,0xffffffffffffffffffffffffffffffff>; }
impl T9o of core::internal::bounded_int::TrimMinHelper<P9e> {type Target=P9o; }
impl S9o of core::internal::bounded_int::SubHelper<P9o,UnitInt<1>> {type Result=P9; }
const ONE1:UnitInt<1> =1;
/// A felt's halves, the high half nonzero and below q^9.
#[inline(always)]
pub(crate) fn hi9r(f:felt252) -> Option<(P9,u128)> {
    match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide((h,l)) => match constrain::<u128,6392178558614694273495691177456939009>(h) {
            Ok(x) => Some((x,l)),
            Err(_) => None,
        },
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => None,
    }
}
/// hi9r for a key felt: a narrow felt (below 2^128) has a zero high half.
#[inline(always)]
pub(crate) fn hi9k(f:felt252) -> Option<(P9,u128)> {
    let (h,l) = match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(l) => (0,l),
    };
    match constrain::<u128,6392178558614694273495691177456939009>(h) {
        Ok(x) => Some((x,l)),
        Err(_) => None,
    }
}
pub(crate) use pqbench_ntt_f1024_pf_record::ci::integer::{U128sFromFelt252Result as UR, u128s_from_felt252 as ufs};
/// hi9k after its split: the high half as a value below q^9, or None.
#[inline(always)]
pub(crate) fn k9(t: (u128, u128)) -> Option<(P9, u128)> {
    let (h, l) = t;
    match constrain::<u128, 6392178558614694273495691177456939009>(h) {
        Ok(x) => Some((x, l)),
        Err(_) => None,
    }
}
#[inline(always)]
pub(crate) fn hi9(f:felt252) -> Option<(P9,u128)> {
    match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f+TWO128) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide((h1,l)) => match constrain::<u128,6392178558614694273495691177456939010>(h1) {
            Ok(x) => match core::internal::bounded_int::trim_min::<P9e>(x) {
                core::internal::OptionRev::Some(y) => Some((bounded_int::sub(y,ONE1),l)),
                core::internal::OptionRev::None => None,
            },
            Err(_) => None,
        },
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => None,
    }
}
type P7e=BoundedInt<0,42326836400273672391635324929>;
type P7o=BoundedInt<1,42326836400273672391635324929>;
impl C7e of ConstrainHelper<u128,42326836400273672391635324930> {type LowT=P7e;type HighT=BoundedInt<42326836400273672391635324930,0xffffffffffffffffffffffffffffffff>; }
impl T7o of core::internal::bounded_int::TrimMinHelper<P7e> {type Target=P7o; }
impl S7o of core::internal::bounded_int::SubHelper<P7o,UnitInt<1>> {type Result=P7; }
/// hi9r for the last felt (high half nonzero and below q^7).
#[inline(always)]
pub(crate) fn hi7r(f:felt252) -> Option<(P7,u128)> {
    let (h,l) = match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(x) => x,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(l) => (0,l),
    };
    match constrain::<u128,42326836400273672391635324929>(h) {
        Ok(x) => Some((x,l)),
        Err(_) => None,
    }
}
/// hi9 for the last felt, whose high half holds seven digits (below q^7).
#[inline(always)]
pub(crate) fn hi7(f:felt252) -> Option<(P7,u128)> {
    match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f+TWO128) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide((h1,l)) => match constrain::<u128,42326836400273672391635324930>(h1) {
            Ok(x) => match core::internal::bounded_int::trim_min::<P7e>(x) {
                core::internal::OptionRev::Some(y) => Some((bounded_int::sub(y,ONE1),l)),
                core::internal::OptionRev::None => None,
            },
            Err(_) => None,
        },
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => None,
    }
}
/// h7 of an already constrained half.
#[inline(always)]
pub(crate) fn h7p(x: P7, nq: NonZero<UnitInt<12289>>) -> (felt252, felt252, felt252, felt252, felt252, felt252, felt252) {
    let (x0, d0) = bounded_int::div_rem(x, nq);
    let (x1, d1) = bounded_int::div_rem(x0, nq);
    let (x2, d2) = bounded_int::div_rem(x1, nq);
    let (x3, d3) = bounded_int::div_rem(x2, nq);
    let (x4, d4) = bounded_int::div_rem(x3, nq);
    let (x5, d5) = bounded_int::div_rem(x4, nq);
    let d6: Zq = x5;
    (upcast(d0), upcast(d1), upcast(d2), upcast(d3), upcast(d4), upcast(d5), upcast(d6))
}
/// h9 of an already constrained half.
#[inline(always)]
pub(crate) fn h9p(x: P9, nq: NonZero<UnitInt<12289>>) -> (felt252, felt252, felt252, felt252, felt252, felt252, felt252, felt252, felt252) {
    let (x0, d0) = bounded_int::div_rem(x, nq);
    let (x1, d1) = bounded_int::div_rem(x0, nq);
    let (x2, d2) = bounded_int::div_rem(x1, nq);
    let (x3, d3) = bounded_int::div_rem(x2, nq);
    let (x4, d4) = bounded_int::div_rem(x3, nq);
    let (x5, d5) = bounded_int::div_rem(x4, nq);
    let (x6, d6) = bounded_int::div_rem(x5, nq);
    let (x7, d7) = bounded_int::div_rem(x6, nq);
    let d8: Zq = x7;
    (upcast(d0), upcast(d1), upcast(d2), upcast(d3), upcast(d4), upcast(d5), upcast(d6), upcast(d7), upcast(d8))
}
/// The 9 base-q digits of one u128 half of a public-key felt, or None if it is not below q^9.
#[inline(always)]
/// v as a half below q^9, if it is one.
pub(crate) fn p9(v: u128) -> Option<P9> {
    match constrain::<u128, 6392178558614694273495691177456939009>(v) { Ok(x) => Some(x), Err(_) => None }
}
pub(crate) fn h9(v: u128, nq: NonZero<UnitInt<12289>>) -> Option<(felt252, felt252, felt252, felt252, felt252, felt252, felt252, felt252, felt252)> {
    let x: P9 = match constrain::<u128, 6392178558614694273495691177456939009>(v) { Ok(x) => x, Err(_) => { return None; } };
    let (x0, d0) = bounded_int::div_rem(x, nq);
    let (x1, d1) = bounded_int::div_rem(x0, nq);
    let (x2, d2) = bounded_int::div_rem(x1, nq);
    let (x3, d3) = bounded_int::div_rem(x2, nq);
    let (x4, d4) = bounded_int::div_rem(x3, nq);
    let (x5, d5) = bounded_int::div_rem(x4, nq);
    let (x6, d6) = bounded_int::div_rem(x5, nq);
    let (x7, d7) = bounded_int::div_rem(x6, nq);
    let d8: Zq = x7;
    Some((upcast(d0), upcast(d1), upcast(d2), upcast(d3), upcast(d4), upcast(d5), upcast(d6), upcast(d7), upcast(d8)))
}
/// The 7 base-q digits of one u128 half of a public-key felt, or None if it is not below q^7.
#[inline(always)]
pub(crate) fn h7(v: u128, nq: NonZero<UnitInt<12289>>) -> Option<(felt252, felt252, felt252, felt252, felt252, felt252, felt252)> {
    let x: P7 = match constrain::<u128, 42326836400273672391635324929>(v) { Ok(x) => x, Err(_) => { return None; } };
    let (x0, d0) = bounded_int::div_rem(x, nq);
    let (x1, d1) = bounded_int::div_rem(x0, nq);
    let (x2, d2) = bounded_int::div_rem(x1, nq);
    let (x3, d3) = bounded_int::div_rem(x2, nq);
    let (x4, d4) = bounded_int::div_rem(x3, nq);
    let (x5, d5) = bounded_int::div_rem(x4, nq);
    let d6: Zq = x5;
    Some((upcast(d0), upcast(d1), upcast(d2), upcast(d3), upcast(d4), upcast(d5), upcast(d6)))
}
/// The 9 base-q digits of an s1 half and a hint half as packed NTT inputs, in coefficient order;
#[inline(always)]
fn digits9(x:P9,y:P9,nq:NonZero<UnitInt<12289>>,mk:u128,hm:u128,points:[crate::hash_to_point::Acc5;9],ref cy:felt252) -> [pqbench_ntt_f1024_pf_record::typed_ntt::Input; 9] {
let[p0,p1,p2,p3,p4,p5,p6,p7,p8] = points;
let(x0,s0) =bounded_int::div_rem(x,nq);
let(y0,d0) =bounded_int::div_rem(y,nq);
let c0=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s0,d0);
let(x1,s1) =bounded_int::div_rem(x0,nq);
let(y1,d1) =bounded_int::div_rem(y0,nq);
let c1=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s1,d1);
let(x2,s2) =bounded_int::div_rem(x1,nq);
let(y2,d2) =bounded_int::div_rem(y1,nq);
let c2=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s2,d2);
let(x3,s3) =bounded_int::div_rem(x2,nq);
let(y3,d3) =bounded_int::div_rem(y2,nq);
let c3=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s3,d3);
let(x4,s4) =bounded_int::div_rem(x3,nq);
let(y4,d4) =bounded_int::div_rem(y3,nq);
let c4=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s4,d4);
let(x5,s5) =bounded_int::div_rem(x4,nq);
let(y5,d5) =bounded_int::div_rem(y4,nq);
let c5=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s5,d5);
let(x6,s6) =bounded_int::div_rem(x5,nq);
let(y6,d6) =bounded_int::div_rem(y5,nq);
let c6=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s6,d6);
let(x7,s7) =bounded_int::div_rem(x6,nq);
let(y7,d7) =bounded_int::div_rem(y6,nq);
let c7=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s7,d7);
let s8:Zq=x7;
let d8:Zq=y7;
let c8=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s8,d8);
cy+=sg3(s0,s1,s2,mk);
cy+=sg3(s3,s4,s5,mk);
cy+=sg3(s6,s7,s8,mk);
cy+=hq3(p0,d0,p1,d1,p2,d2,hm);
cy+=hq3(p3,d3,p4,d4,p5,d5,hm);
cy+=hq3(p6,d6,p7,d7,p8,d8,hm);
[c0,c1,c2,c3,c4,c5,c6,c7,c8]
}
/// The 7 base-q digits of the last s1 and hint high halves, as digits9.
#[inline(always)]
fn digits7(x:P7,y:P7,nq:NonZero<UnitInt<12289>>,mk:u128,hm:u128,points:[crate::hash_to_point::Acc5;7],ref cy:felt252) -> [pqbench_ntt_f1024_pf_record::typed_ntt::Input; 7] {
let[p0,p1,p2,p3,p4,p5,p6] = points;
let(x0,s0) =bounded_int::div_rem(x,nq);
let(y0,d0) =bounded_int::div_rem(y,nq);
let c0=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s0,d0);
let(x1,s1) =bounded_int::div_rem(x0,nq);
let(y1,d1) =bounded_int::div_rem(y0,nq);
let c1=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s1,d1);
let(x2,s2) =bounded_int::div_rem(x1,nq);
let(y2,d2) =bounded_int::div_rem(y1,nq);
let c2=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s2,d2);
let(x3,s3) =bounded_int::div_rem(x2,nq);
let(y3,d3) =bounded_int::div_rem(y2,nq);
let c3=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s3,d3);
let(x4,s4) =bounded_int::div_rem(x3,nq);
let(y4,d4) =bounded_int::div_rem(y3,nq);
let c4=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s4,d4);
let(x5,s5) =bounded_int::div_rem(x4,nq);
let(y5,d5) =bounded_int::div_rem(y4,nq);
let c5=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s5,d5);
let s6:Zq=x5;
let d6:Zq=y5;
let c6=pqbench_ntt_f1024_pf_record::typed_ntt::pack(s6,d6);
cy+=sg3(s0,s1,s2,mk);
cy+=sg3(s3,s4,s5,mk);
cy+=hq3(p0,d0,p1,d1,p2,d2,hm);
cy+=hq3(p3,d3,p4,d4,p5,d5,hm);
cy+=hq2(p6,d6,s6,hm);
[c0,c1,c2,c3,c4,c5,c6]
}
/// nq, mk, hm: q and the packed norms' flag masks (packing::cells).
#[inline(always)]
pub fn uw7(sig:Span<felt252>,point:Span<crate::hash_to_point::Acc5>,nq:NonZero<UnitInt<12289>>,mk:u128,hm:u128) -> St {
uw(uw(uw(uw(uw(uw(uw((sig,point,nq,mk,hm,OFJ,array![]))))))))
}
/// Every felt pair left in ss (s1 felt, hint felt 59 on), 18 digit pairs each appended.
fn ex_pairs(ref ss:Span<felt252>,ref hh:Span<felt252>,ref pt:Span<crate::hash_to_point::Acc5>,ref cy:felt252,ref ks:Array<pqbench_ntt_f1024_pf_record::typed_ntt::Input>) -> Option<()> {
let Some(fs)=ss.pop_front() else {return Some(());};
let fs=*fs;
let fh=*hh.pop_front()?;
let (xl,xh,yl,yh)=chke(fs,fh)?;
let pa=*pt.multi_pop_front::<9>()?;
let (ka,c1)=d9(xl,yl,pa,cy);
let pb=*pt.multi_pop_front::<9>()?;
let (kb,c2)=d9(xh,yh,pb,c1);
cy=c2;
let [a0,a1,a2,a3,a4,a5,a6,a7,a8]=ka;
let [b0,b1,b2,b3,b4,b5,b6,b7,b8]=kb;
ks.append(a0);ks.append(a1);ks.append(a2);ks.append(a3);ks.append(a4);ks.append(a5);ks.append(a6);ks.append(a7);ks.append(a8);
ks.append(b0);ks.append(b1);ks.append(b2);ks.append(b3);ks.append(b4);ks.append(b5);ks.append(b6);ks.append(b7);ks.append(b8);
ex_pairs(ref ss,ref hh,ref pt,ref cy,ref ks)
}
/// digits9 as a call: the digit pairs and the norm sum with this half's terms added.
#[inline(never)]
fn d9(x:P9,y:P9,points:Box<[crate::hash_to_point::Acc5;9]>,cy:felt252) -> ([pqbench_ntt_f1024_pf_record::typed_ntt::Input;9],felt252) {
let mut cy=cy;
let[p0,p1,p2,p3,p4,p5,p6,p7,p8] = points.unbox();
let ([s0,s1,s2,s3,s4,s5,s6,s7,s8],[d0,d1,d2,d3,d4,d5,d6,d7,d8])=dec18(x,y,NQ);
cy+=sgh3(s0,s1,s2,p0,d0,p1,d1,p2,d2);
cy+=sgh3(s3,s4,s5,p3,d3,p4,d4,p5,d5);
cy+=sgh3(s6,s7,s8,p6,d6,p7,d7,p8,d8);
([pqbench_ntt_f1024_pf_record::typed_ntt::pack(s0,d0),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s1,d1),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s2,d2),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s3,d3),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s4,d4),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s5,d5),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s6,d6),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s7,d7),pqbench_ntt_f1024_pf_record::typed_ntt::pack(s8,d8)],cy)
}
/// d9's sg3 + hq3 terms of one digit triple, out of line (cold decoder only).
#[inline(never)]
fn sgh3(s0:Zq,s1:Zq,s2:Zq,p0:crate::hash_to_point::Acc5,d0:Zq,p1:crate::hash_to_point::Acc5,d1:Zq,p2:crate::hash_to_point::Acc5,d2:Zq) -> felt252 {
sg3(s0,s1,s2,N4MASK3)+hq3(p0,d0,p1,d1,p2,d2,HPM)
}
/// The 9 base-q digits of two P9 halves (cold decoders d9 and exact9 share this body).
#[inline(never)]
pub(crate) fn dec18(xs:P9,xh:P9,nq:NonZero<UnitInt<12289>>) -> ([Zq;9],[Zq;9]) {
let(x0,s0) =bounded_int::div_rem(xs,nq);
let(y0,h0) =bounded_int::div_rem(xh,nq);
let(x1,s1) =bounded_int::div_rem(x0,nq);
let(y1,h1) =bounded_int::div_rem(y0,nq);
let(x2,s2) =bounded_int::div_rem(x1,nq);
let(y2,h2) =bounded_int::div_rem(y1,nq);
let(x3,s3) =bounded_int::div_rem(x2,nq);
let(y3,h3) =bounded_int::div_rem(y2,nq);
let(x4,s4) =bounded_int::div_rem(x3,nq);
let(y4,h4) =bounded_int::div_rem(y3,nq);
let(x5,s5) =bounded_int::div_rem(x4,nq);
let(y5,h5) =bounded_int::div_rem(y4,nq);
let(x6,s6) =bounded_int::div_rem(x5,nq);
let(y6,h6) =bounded_int::div_rem(y5,nq);
let(x7,s7) =bounded_int::div_rem(x6,nq);
let(y7,h7) =bounded_int::div_rem(y6,nq);
([s0,s1,s2,s3,s4,s5,s6,s7,x7],[h0,h1,h2,h3,h4,h5,h6,h7,y7])
}
/// Every 4 digit pairs (coefficients 4m to 4m+3) as the two pairs (4m, 4m+2) and (4m+1, 4m+3).
fn ex_join(ref ks:Span<pqbench_ntt_f1024_pf_record::typed_ntt::Input>,ref eo:Array<J>) {
if let Some(b)=ks.multi_pop_front::<4>() {
let [k0,k1,k2,k3]=(*b).unbox();
eo.append(J{a:k0,b:k2});
eo.append(J{a:k1,b:k3});
ex_join(ref ks,ref eo);
}
}
/// uw7's continuation for a block its fast path could not take (a narrow felt, or a non-canonical
/// one, which ex_pairs rejects). ub leaves mk = 0, its norm sum and eo as they were before that
/// block, and the signature length left after the block's 8 felts; the block and every later one
/// are decoded here, narrow felts included, to the state ubt expects.
#[inline(never)]
pub(crate) fn slow7(sig:Span<felt252>,point:Span<crate::hash_to_point::Acc5>,t:St) -> Option<St> {
match core::gas::withdraw_gas() { Some(_) => {}, None => { return None; } }
let (lsp,_,nq,_,_,cy,eo)=t;
let left=lsp.len();
let (nq,mk,hm)=cells();
let lb:BoundedInt<60,108>=match core::internal::bounded_int::downcast(left) {Some(v) => v,None => { return None; },};
let dn:BoundedInt<0,48>=bounded_int::sub(L108,lb);
let (k,r)=bounded_int::div_rem(dn,N8);
let r:felt252=upcast(r);
if r!=0 {return None;}
let k:BoundedInt<0,6>=k;
let done:u32=upcast(bounded_int::mul(k,C8));
let n:u32=upcast(bounded_int::sub(C56,bounded_int::mul(k,C8)));
let mut ss=sig.slice(done,n);let mut hh=sig.slice(upcast(bounded_int::add(bounded_int::mul(k,C8),C59)),n);let mut pt=point.slice(upcast(bounded_int::mul(k,C144)),upcast(bounded_int::sub(C1024,bounded_int::mul(k,C144))));let mut cy=cy;let mut ks:Array<pqbench_ntt_f1024_pf_record::typed_ntt::Input>=array![];
let Some(_)=ex_pairs(ref ss,ref hh,ref pt,ref cy,ref ks) else { return None; };
let mut kv=ks.span();let mut eo=eo;
ex_join(ref kv,ref eo);
Some((sig.slice(56,60),pt,nq,mk,hm,cy,eo))
}
const L108:UnitInt<108> =108;
const N8:NonZero<UnitInt<8>> =8;
const C8:UnitInt<8> =8;
const C56:UnitInt<56> =56;
const C59:UnitInt<59> =59;
const C144:UnitInt<144> =144;
const C1024:UnitInt<1024> =1024;
impl SlL of SubHelper<UnitInt<108>,BoundedInt<60,108>> {type Result=BoundedInt<0,48>; }
impl SlD of DivRemHelper<BoundedInt<0,48>,UnitInt<8>> {type DivT=BoundedInt<0,6>;type RemT=BoundedInt<0,7>; }
impl SlM8 of MulHelper<BoundedInt<0,6>,UnitInt<8>> {type Result=BoundedInt<0,48>; }
impl SlN of SubHelper<UnitInt<56>,BoundedInt<0,48>> {type Result=BoundedInt<8,56>; }
impl SlH of AddHelper<BoundedInt<0,48>,UnitInt<59>> {type Result=BoundedInt<59,107>; }
impl SlM144 of MulHelper<BoundedInt<0,6>,UnitInt<144>> {type Result=BoundedInt<0,864>; }
impl SlP of SubHelper<UnitInt<1024>,BoundedInt<0,864>> {type Result=BoundedInt<160,1024>; }
/// The decoder state: signature, points left, q, norm masks, norm so far, eo.
pub(crate) type St=(Span<felt252>,Span<crate::hash_to_point::Acc5>,NonZero<UnitInt<12289>>,u128,u128,felt252,Array<J>);
/// ub as a call without gas builtin; the state is one tuple so nested calls pass
#[inline(never)]
fn uw(t:St) -> St {
ub(t)
}
/// The state after 8 felt pairs and 144 points, or None for a non-canonical felt.
#[inline(always)]
fn ub(t:St) -> St {
let (sp,pt,nq,mk,hm,cy,eo)=t;
let mut eo=eo;let mut cy=cy;let mut pt=pt;let mut sp=sp;
if let Some(pq)=pt.multi_pop_front::<144>(){
let mut hs=sp;
let Some(blk)=sp.multi_pop_front::<8>() else { return (sp,array![].span(),NQ,0,0,cy,eo); };
let [s0,s1,s2,s3,s4,s5,s6,s7]=blk.unbox();
let [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,h0,h1,h2,h3,h4,h5,h6,h7]=(*match hs.multi_pop_front::<67>() {Some(b) => b,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },}).unbox();
let (xl0,xh0,yl0,yh0)=match chk(s0,h0) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl1,xh1,yl1,yh1)=match chk(s1,h1) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl2,xh2,yl2,yh2)=match chk(s2,h2) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl3,xh3,yl3,yh3)=match chk(s3,h3) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl4,xh4,yl4,yh4)=match chk(s4,h4) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl5,xh5,yl5,yh5)=match chk(s5,h5) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl6,xh6,yl6,yh6)=match chk(s6,h6) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let (xl7,xh7,yl7,yh7)=match chk(s7,h7) {Some(v) => v,None => { return (sp,array![].span(),NQ,0,0,cy,eo); },};
let [q0,q1,q2,q3,q4,q5,q6,q7,q8,q9,q10,q11,q12,q13,q14,q15,q16,q17,q18,q19,q20,q21,q22,q23,q24,q25,q26,q27,q28,q29,q30,q31,q32,q33,q34,q35,q36,q37,q38,q39,q40,q41,q42,q43,q44,q45,q46,q47,q48,q49,q50,q51,q52,q53,q54,q55,q56,q57,q58,q59,q60,q61,q62,q63,q64,q65,q66,q67,q68,q69,q70,q71,q72,q73,q74,q75,q76,q77,q78,q79,q80,q81,q82,q83,q84,q85,q86,q87,q88,q89,q90,q91,q92,q93,q94,q95,q96,q97,q98,q99,q100,q101,q102,q103,q104,q105,q106,q107,q108,q109,q110,q111,q112,q113,q114,q115,q116,q117,q118,q119,q120,q121,q122,q123,q124,q125,q126,q127,q128,q129,q130,q131,q132,q133,q134,q135,q136,q137,q138,q139,q140,q141,q142,q143]=(*pq).unbox();
let[k0,k1,k2,k3,k4,k5,k6,k7,k8]=digits9(xl0,yl0,nq,mk,hm,[q0,q1,q2,q3,q4,q5,q6,q7,q8],ref cy);
eo.append(J{a:k0,b:k2});
eo.append(J{a:k1,b:k3});
eo.append(J{a:k4,b:k6});
eo.append(J{a:k5,b:k7});
let[k9,k10,k11,k12,k13,k14,k15,k16,k17]=digits9(xh0,yh0,nq,mk,hm,[q9,q10,q11,q12,q13,q14,q15,q16,q17],ref cy);
eo.append(J{a:k8,b:k10});
eo.append(J{a:k9,b:k11});
eo.append(J{a:k12,b:k14});
eo.append(J{a:k13,b:k15});
let[k18,k19,k20,k21,k22,k23,k24,k25,k26]=digits9(xl1,yl1,nq,mk,hm,[q18,q19,q20,q21,q22,q23,q24,q25,q26],ref cy);
eo.append(J{a:k16,b:k18});
eo.append(J{a:k17,b:k19});
eo.append(J{a:k20,b:k22});
eo.append(J{a:k21,b:k23});
eo.append(J{a:k24,b:k26});
let[k27,k28,k29,k30,k31,k32,k33,k34,k35]=digits9(xh1,yh1,nq,mk,hm,[q27,q28,q29,q30,q31,q32,q33,q34,q35],ref cy);
eo.append(J{a:k25,b:k27});
eo.append(J{a:k28,b:k30});
eo.append(J{a:k29,b:k31});
eo.append(J{a:k32,b:k34});
eo.append(J{a:k33,b:k35});
let[k36,k37,k38,k39,k40,k41,k42,k43,k44]=digits9(xl2,yl2,nq,mk,hm,[q36,q37,q38,q39,q40,q41,q42,q43,q44],ref cy);
eo.append(J{a:k36,b:k38});
eo.append(J{a:k37,b:k39});
eo.append(J{a:k40,b:k42});
eo.append(J{a:k41,b:k43});
let[k45,k46,k47,k48,k49,k50,k51,k52,k53]=digits9(xh2,yh2,nq,mk,hm,[q45,q46,q47,q48,q49,q50,q51,q52,q53],ref cy);
eo.append(J{a:k44,b:k46});
eo.append(J{a:k45,b:k47});
eo.append(J{a:k48,b:k50});
eo.append(J{a:k49,b:k51});
let[k54,k55,k56,k57,k58,k59,k60,k61,k62]=digits9(xl3,yl3,nq,mk,hm,[q54,q55,q56,q57,q58,q59,q60,q61,q62],ref cy);
eo.append(J{a:k52,b:k54});
eo.append(J{a:k53,b:k55});
eo.append(J{a:k56,b:k58});
eo.append(J{a:k57,b:k59});
eo.append(J{a:k60,b:k62});
let[k63,k64,k65,k66,k67,k68,k69,k70,k71]=digits9(xh3,yh3,nq,mk,hm,[q63,q64,q65,q66,q67,q68,q69,q70,q71],ref cy);
eo.append(J{a:k61,b:k63});
eo.append(J{a:k64,b:k66});
eo.append(J{a:k65,b:k67});
eo.append(J{a:k68,b:k70});
eo.append(J{a:k69,b:k71});
let[k72,k73,k74,k75,k76,k77,k78,k79,k80]=digits9(xl4,yl4,nq,mk,hm,[q72,q73,q74,q75,q76,q77,q78,q79,q80],ref cy);
eo.append(J{a:k72,b:k74});
eo.append(J{a:k73,b:k75});
eo.append(J{a:k76,b:k78});
eo.append(J{a:k77,b:k79});
let[k81,k82,k83,k84,k85,k86,k87,k88,k89]=digits9(xh4,yh4,nq,mk,hm,[q81,q82,q83,q84,q85,q86,q87,q88,q89],ref cy);
eo.append(J{a:k80,b:k82});
eo.append(J{a:k81,b:k83});
eo.append(J{a:k84,b:k86});
eo.append(J{a:k85,b:k87});
let[k90,k91,k92,k93,k94,k95,k96,k97,k98]=digits9(xl5,yl5,nq,mk,hm,[q90,q91,q92,q93,q94,q95,q96,q97,q98],ref cy);
eo.append(J{a:k88,b:k90});
eo.append(J{a:k89,b:k91});
eo.append(J{a:k92,b:k94});
eo.append(J{a:k93,b:k95});
eo.append(J{a:k96,b:k98});
let[k99,k100,k101,k102,k103,k104,k105,k106,k107]=digits9(xh5,yh5,nq,mk,hm,[q99,q100,q101,q102,q103,q104,q105,q106,q107],ref cy);
eo.append(J{a:k97,b:k99});
eo.append(J{a:k100,b:k102});
eo.append(J{a:k101,b:k103});
eo.append(J{a:k104,b:k106});
eo.append(J{a:k105,b:k107});
let[k108,k109,k110,k111,k112,k113,k114,k115,k116]=digits9(xl6,yl6,nq,mk,hm,[q108,q109,q110,q111,q112,q113,q114,q115,q116],ref cy);
eo.append(J{a:k108,b:k110});
eo.append(J{a:k109,b:k111});
eo.append(J{a:k112,b:k114});
eo.append(J{a:k113,b:k115});
let[k117,k118,k119,k120,k121,k122,k123,k124,k125]=digits9(xh6,yh6,nq,mk,hm,[q117,q118,q119,q120,q121,q122,q123,q124,q125],ref cy);
eo.append(J{a:k116,b:k118});
eo.append(J{a:k117,b:k119});
eo.append(J{a:k120,b:k122});
eo.append(J{a:k121,b:k123});
let[k126,k127,k128,k129,k130,k131,k132,k133,k134]=digits9(xl7,yl7,nq,mk,hm,[q126,q127,q128,q129,q130,q131,q132,q133,q134],ref cy);
eo.append(J{a:k124,b:k126});
eo.append(J{a:k125,b:k127});
eo.append(J{a:k128,b:k130});
eo.append(J{a:k129,b:k131});
eo.append(J{a:k132,b:k134});
let[k135,k136,k137,k138,k139,k140,k141,k142,k143]=digits9(xh7,yh7,nq,mk,hm,[q135,q136,q137,q138,q139,q140,q141,q142,q143],ref cy);
eo.append(J{a:k133,b:k135});
eo.append(J{a:k136,b:k138});
eo.append(J{a:k137,b:k139});
eo.append(J{a:k140,b:k142});
eo.append(J{a:k141,b:k143});
return (sp,pt,nq,mk,hm,cy,eo);
}
(sp,pt,nq,mk,hm,cy,eo)
}
/// The last felt pair and 16 points, then the packed norm.
#[inline(always)]
pub(crate) fn ubt(t:St) -> UbtR {
let (sp,pt,nq,mk,hm,cy,eo)=t;
let mut eo=eo;let mut cy=cy;let mut pt=pt;let mut sp=sp;
let lb: Option<@Box<[felt252;60]>> = sp.try_into();
let Some(lb)=lb else { return UbtR::Fail; };
let [last_s,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,last_h]=(*lb).unbox();
let (xh,sl)=match hi7w(last_s) {H7::Ok(v) => v,H7::Narrow(_) => { return UbtR::Slow((sp,pt,nq,mk,hm,cy,eo)); },H7::Bad => { return UbtR::Fail; }};
let (yh,hl)=match hi7w(last_h) {H7::Ok(v) => v,H7::Narrow(_) => { return UbtR::Slow((sp,pt,nq,mk,hm,cy,eo)); },H7::Bad => { return UbtR::Fail; }};
let xl:P9=match constrain::<u128,6392178558614694273495691177456939009>(sl) {Ok(x) => x,Err(_) => {return UbtR::Fail; } };
let yl:P9=match constrain::<u128,6392178558614694273495691177456939009>(hl) {Ok(x) => x,Err(_) => {return UbtR::Fail; } };
let[p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15]=(*pt.multi_pop_front::<16>().unwrap()).unbox();
let[k0,k1,k2,k3,k4,k5,k6,k7,k8]=digits9(xl,yl,nq,mk,hm,[p0,p1,p2,p3,p4,p5,p6,p7,p8],ref cy);
eo.append(J{a:k0,b:k2});
eo.append(J{a:k1,b:k3});
eo.append(J{a:k4,b:k6});
eo.append(J{a:k5,b:k7});
let[k9,k10,k11,k12,k13,k14,k15]=digits7(xh,yh,nq,mk,hm,[p9,p10,p11,p12,p13,p14,p15],ref cy);
eo.append(J{a:k8,b:k10});
eo.append(J{a:k9,b:k11});
eo.append(J{a:k12,b:k14});
let ev=eo.span();
eo.append(J{a:k13,b:k15});
let sn=match s1_packed_norm(cy) {Option::Some(v) => v,Option::None=> {return UbtR::Fail; } };
UbtR::Ok((ev,eo,sn))
}

/// ubt's result.
pub(crate) enum UbtR { Ok: (Span<J>,Array<J>,SN), Slow: St, Fail: () }
pub(crate) enum H7 { Ok: (P7,u128), Narrow: u128, Bad: () }
/// hi7 without the +2^128 bias: Wide felts only; a narrow felt is reported, not decoded.
#[inline(always)]
pub(crate) fn hi7w(f:felt252) -> H7 {
    match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(f) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide((h,l)) => match constrain::<u128,42326836400273672391635324929>(h) {
            Ok(x) => H7::Ok((x,l)),
            Err(_) => H7::Bad,
        },
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(l) => H7::Narrow(l),
    }
}
/// ubt for vslow (cold): the low half through the shared d9 call instead of an inline digits9.
#[inline(always)]
pub(crate) fn ubtc(t:St) -> Option<(Span<J>,Array<J>,SN)> {
let (sp,pt,nq,mk,hm,cy,eo)=t;
let mut eo=eo;let mut pt=pt;let mut sp=sp;
let lb: Option<@Box<[felt252;60]>> = sp.try_into();
let Some(lb)=lb else { return None; };
let [last_s,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,last_h]=(*lb).unbox();
let (xh,sl)=hi7(last_s)?;
let (yh,hl)=hi7(last_h)?;
let xl:P9=match constrain::<u128,6392178558614694273495691177456939009>(sl) {Ok(x) => x,Err(_) => {return None; } };
let yl:P9=match constrain::<u128,6392178558614694273495691177456939009>(hl) {Ok(x) => x,Err(_) => {return None; } };
let Some(pb)=pt.multi_pop_front::<9>() else { return None; };
let Some(pc)=pt.multi_pop_front::<7>() else { return None; };
let ([k0,k1,k2,k3,k4,k5,k6,k7,k8],cy)=d9(xl,yl,*pb,cy);
let mut cy=cy;
let[k9,k10,k11,k12,k13,k14,k15]=digits7(xh,yh,nq,mk,hm,(*pc).unbox(),ref cy);
eo.append(J{a:k0,b:k2});
eo.append(J{a:k1,b:k3});
eo.append(J{a:k4,b:k6});
eo.append(J{a:k5,b:k7});
eo.append(J{a:k8,b:k10});
eo.append(J{a:k9,b:k11});
eo.append(J{a:k12,b:k14});
let ev=eo.span();
eo.append(J{a:k13,b:k15});
let sn=match s1_packed_norm(cy) {Option::Some(v) => v,Option::None=> {return None; } };
Some((ev,eo,sn))
}
/// One s1 felt and one hint felt, checked canonical with a nonzero high half and split:
#[inline(always)]
fn chk(fs:felt252,fh:felt252) -> Option<(P9,P9,P9,P9)> {
let (xh,sl)=hi9r(fs)?;
let (yh,hl)=hi9r(fh)?;
let xl:P9=match constrain::<u128,6392178558614694273495691177456939009>(sl) {Ok(x) => x,Err(_) => {return None; } };
let yl:P9=match constrain::<u128,6392178558614694273495691177456939009>(hl) {Ok(x) => x,Err(_) => {return None; } };
Some((xl,xh,yl,yh))
}
/// chk with hi9: a zero high half is accepted.
#[inline(always)]
fn chke(fs:felt252,fh:felt252) -> Option<(P9,P9,P9,P9)> {
let (xh,sl)=hi9(fs)?;
let (yh,hl)=hi9(fh)?;
let xl:P9=match constrain::<u128,6392178558614694273495691177456939009>(sl) {Ok(x) => x,Err(_) => {return None; } };
let yl:P9=match constrain::<u128,6392178558614694273495691177456939009>(hl) {Ok(x) => x,Err(_) => {return None; } };
Some((xl,xh,yl,yh))
}

/// q as the divisor of the exact norm's digit divisions.
#[inline(always)]
pub(crate) fn qcell() -> NonZero<UnitInt<12289>> {
    NQ
}

/// q and the packed norms' flag masks, for the decoder and the merge check.
#[inline(always)]
pub(crate) fn cells() -> (NonZero<UnitInt<12289>>, u128, u128) {
    (NQ, N4MASK3, HPM)
}

/// The exact squared norm, for a packed norm just above the bound.
#[inline(always)]
pub fn exact_norm(s1p:Span<felt252>,hp:Span<felt252>,point:Span<crate::hash_to_point::Acc5>) -> felt252 {
let nq=qcell();
let mut n:felt252=0;
let mut sp=s1p;
let mut hp=hp;
let mut pt=point.slice(0,1024);
while let Some(vh)=hp.pop_front(){
let vh:u256= (*vh).into();
let Some(vs)=sp.pop_front() else { break; };
let vs:u256= (*vs).into();
let Some(pl)=pt.multi_pop_front::<9>() else { break; };
n+=exact9(vs.low,vh.low,*pl,nq);
let ph=match pt.multi_pop_front::<9>() {
Some(b) => *b,
None => {
let Some(b)=pt.multi_pop_front::<7>() else { break; };
let [a0,a1,a2,a3,a4,a5,a6]=(*b).unbox();
BoxTrait::new([a0,a1,a2,a3,a4,a5,a6,0,0])
},
};
n+=exact9(vs.high,vh.high,ph,nq);
}
n
}
/// One half pair's nine norm terms.
#[inline(never)]
fn exact9(s:u128,h:u128,p:Box<[crate::hash_to_point::Acc5;9]>,nq:NonZero<UnitInt<12289>>) -> felt252 {
let xs:P9=match constrain::<u128,6392178558614694273495691177456939009>(s) {Ok(x) => x,Err(_) => {return 0;} };
let xh:P9=match constrain::<u128,6392178558614694273495691177456939009>(h) {Ok(x) => x,Err(_) => {return 0;} };
let [p0,p1,p2,p3,p4,p5,p6,p7,p8]=p.unbox();
let ([s0,s1,s2,s3,s4,s5,s6,s7,s8],[h0,h1,h2,h3,h4,h5,h6,h7,h8])=dec18(xs,xh,nq);
et(s0,h0,p0,nq)+et(s1,h1,p1,nq)+et(s2,h2,p2,nq)+et(s3,h3,p3,nq)+et(s4,h4,p4,nq)+et(s5,h5,p5,nq)+et(s6,h6,p6,nq)+et(s7,h7,p7,nq)+et(s8,h8,p8,nq)
}
/// centered(s)^2 + centered(p - h)^2 for one digit pair.
#[inline(never)]
fn et(s:Zq,h:Zq,p:crate::hash_to_point::Acc5,nq:NonZero<UnitInt<12289>>) -> felt252 {
sq(s)+cdiff(p,h,nq)
}
