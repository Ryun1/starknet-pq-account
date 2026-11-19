//! The Falcon-1024 verification equation over unpacked coefficients.
//!
//! The signer supplies mul_hint = s1 * h; two forward NTTs and a pointwise check bind it, since
//! NTT(s1) * h_ntt == NTT(mul_hint) mod q holds exactly when mul_hint is s1 * h. The norm is then
//! ||message point - mul_hint||^2 + ||s1||^2 over centered coefficients.


/// Falcon-1024's squared norm bound (falcon.py's sig_bound for n = 1024).
use pqbench_ntt_f1024_pf_record::J;
use pqbench_ntt_f1024_pf_record::typed_ntt::{Input, RawIn, Word, Wv, typed_ntt};
use pqbench_ntt_f1024_pf_record::ci::bounded_int::{BoundedInt, DivRemHelper, UnitInt, bounded_int, upcast};

pub const SIG_BOUND: u64 = 70265242;
const Q: u64 = 12289;
/// q^-1 in the Stark field.
const Q_INV: felt252 = 0x590625348ee7b13ed5063a897278482929cf2104a53c8ebd06ba86c7dbd6164;
const HALF_Q: u64 = 6144;

/// The NTT check over eo (s1 - 2^123 * hint, even and odd halves interleaved).
#[inline(always)]
pub fn verify_with_hint(
    ev: Span<pqbench_ntt_f1024_pf_record::J>, eo: Span<pqbench_ntt_f1024_pf_record::J>, pk: Span<felt252>, nq: NonZero<UnitInt<12289>>,
) -> bool {
    let mut ot = eo;
    let Some(ob) = ot.multi_pop_back::<511>() else { return false; };
    let Some(eb) = ev.try_into() else { return false; };
    let e = half_ntt(eb);
    let o = half_ntt(ob);
    let (_, _, _, _, _, _, u, v) = merge_check(o, e, pk, lane_base(), nq);
    div_ok(u) && div_ok(v)
}

/// verify for a packed norm above the bound, decided by the exact norm.
#[inline(never)]
pub(crate) fn rare(
    n: u128, ev: Span<pqbench_ntt_f1024_pf_record::J>, eo: Array<pqbench_ntt_f1024_pf_record::J>, pk: Span<felt252>, nq: NonZero<UnitInt<12289>>,
    signature: Span<felt252>, point: Span<crate::hash_to_point::Acc5>,
) -> bool {
    n <= 84200968 && {
        let mut hint = signature;
        let Some(_) = hint.multi_pop_front::<59>() else { return false; };
        let Some(e): Option<u128> = crate::packing::exact_norm(signature, hint, point).try_into() else { return false; };
        e <= 70265242
    } && vwh(ev, eo, pk, nq)
}

/// verify_with_hint out of line for the cold callers (rare, vslow).
#[inline(never)]
pub(crate) fn vwh(ev: Span<pqbench_ntt_f1024_pf_record::J>, eo: Array<pqbench_ntt_f1024_pf_record::J>, pk: Span<felt252>, nq: NonZero<UnitInt<12289>>) -> bool {
    verify_with_hint(ev, eo.span(), pk, nq)
}

/// The typed NTT of one half: the even positions of a 511-element window.
#[inline(never)]
pub(crate) fn half_ntt(b: @Box<[pqbench_ntt_f1024_pf_record::J; 511]>) -> (Span<pqbench_ntt_f1024_pf_record::F>, [Word; 8]) implicits(core::RangeCheck) {
    core::gas::redeposit_gas();
    let [j0,_,j1,_,j2,_,j3,_,j4,_,j5,_,j6,_,j7,_,j8,_,j9,_,j10,_,j11,_,j12,_,j13,_,j14,_,j15,_,j16,_,j17,_,j18,_,j19,_,j20,_,j21,_,j22,_,j23,_,j24,_,j25,_,j26,_,j27,_,j28,_,j29,_,j30,_,j31,_,j32,_,j33,_,j34,_,j35,_,j36,_,j37,_,j38,_,j39,_,j40,_,j41,_,j42,_,j43,_,j44,_,j45,_,j46,_,j47,_,j48,_,j49,_,j50,_,j51,_,j52,_,j53,_,j54,_,j55,_,j56,_,j57,_,j58,_,j59,_,j60,_,j61,_,j62,_,j63,_,j64,_,j65,_,j66,_,j67,_,j68,_,j69,_,j70,_,j71,_,j72,_,j73,_,j74,_,j75,_,j76,_,j77,_,j78,_,j79,_,j80,_,j81,_,j82,_,j83,_,j84,_,j85,_,j86,_,j87,_,j88,_,j89,_,j90,_,j91,_,j92,_,j93,_,j94,_,j95,_,j96,_,j97,_,j98,_,j99,_,j100,_,j101,_,j102,_,j103,_,j104,_,j105,_,j106,_,j107,_,j108,_,j109,_,j110,_,j111,_,j112,_,j113,_,j114,_,j115,_,j116,_,j117,_,j118,_,j119,_,j120,_,j121,_,j122,_,j123,_,j124,_,j125,_,j126,_,j127,_,j128,_,j129,_,j130,_,j131,_,j132,_,j133,_,j134,_,j135,_,j136,_,j137,_,j138,_,j139,_,j140,_,j141,_,j142,_,j143,_,j144,_,j145,_,j146,_,j147,_,j148,_,j149,_,j150,_,j151,_,j152,_,j153,_,j154,_,j155,_,j156,_,j157,_,j158,_,j159,_,j160,_,j161,_,j162,_,j163,_,j164,_,j165,_,j166,_,j167,_,j168,_,j169,_,j170,_,j171,_,j172,_,j173,_,j174,_,j175,_,j176,_,j177,_,j178,_,j179,_,j180,_,j181,_,j182,_,j183,_,j184,_,j185,_,j186,_,j187,_,j188,_,j189,_,j190,_,j191,_,j192,_,j193,_,j194,_,j195,_,j196,_,j197,_,j198,_,j199,_,j200,_,j201,_,j202,_,j203,_,j204,_,j205,_,j206,_,j207,_,j208,_,j209,_,j210,_,j211,_,j212,_,j213,_,j214,_,j215,_,j216,_,j217,_,j218,_,j219,_,j220,_,j221,_,j222,_,j223,_,j224,_,j225,_,j226,_,j227,_,j228,_,j229,_,j230,_,j231,_,j232,_,j233,_,j234,_,j235,_,j236,_,j237,_,j238,_,j239,_,j240,_,j241,_,j242,_,j243,_,j244,_,j245,_,j246,_,j247,_,j248,_,j249,_,j250,_,j251,_,j252,_,j253,_,j254,_,j255]=(*b).unbox();

let J{a:x0,b:x1}=j0;let J{a:x2,b:x3}=j1;let J{a:x4,b:x5}=j2;let J{a:x6,b:x7}=j3;let J{a:x8,b:x9}=j4;let J{a:x10,b:x11}=j5;let J{a:x12,b:x13}=j6;let J{a:x14,b:x15}=j7;let J{a:x16,b:x17}=j8;let J{a:x18,b:x19}=j9;let J{a:x20,b:x21}=j10;let J{a:x22,b:x23}=j11;let J{a:x24,b:x25}=j12;let J{a:x26,b:x27}=j13;let J{a:x28,b:x29}=j14;let J{a:x30,b:x31}=j15;let J{a:x32,b:x33}=j16;let J{a:x34,b:x35}=j17;let J{a:x36,b:x37}=j18;let J{a:x38,b:x39}=j19;let J{a:x40,b:x41}=j20;let J{a:x42,b:x43}=j21;let J{a:x44,b:x45}=j22;let J{a:x46,b:x47}=j23;let J{a:x48,b:x49}=j24;let J{a:x50,b:x51}=j25;let J{a:x52,b:x53}=j26;let J{a:x54,b:x55}=j27;let J{a:x56,b:x57}=j28;let J{a:x58,b:x59}=j29;let J{a:x60,b:x61}=j30;let J{a:x62,b:x63}=j31;let J{a:x64,b:x65}=j32;let J{a:x66,b:x67}=j33;let J{a:x68,b:x69}=j34;let J{a:x70,b:x71}=j35;let J{a:x72,b:x73}=j36;let J{a:x74,b:x75}=j37;let J{a:x76,b:x77}=j38;let J{a:x78,b:x79}=j39;let J{a:x80,b:x81}=j40;let J{a:x82,b:x83}=j41;let J{a:x84,b:x85}=j42;let J{a:x86,b:x87}=j43;let J{a:x88,b:x89}=j44;let J{a:x90,b:x91}=j45;let J{a:x92,b:x93}=j46;let J{a:x94,b:x95}=j47;let J{a:x96,b:x97}=j48;let J{a:x98,b:x99}=j49;let J{a:x100,b:x101}=j50;let J{a:x102,b:x103}=j51;let J{a:x104,b:x105}=j52;let J{a:x106,b:x107}=j53;let J{a:x108,b:x109}=j54;let J{a:x110,b:x111}=j55;let J{a:x112,b:x113}=j56;let J{a:x114,b:x115}=j57;let J{a:x116,b:x117}=j58;let J{a:x118,b:x119}=j59;let J{a:x120,b:x121}=j60;let J{a:x122,b:x123}=j61;let J{a:x124,b:x125}=j62;let J{a:x126,b:x127}=j63;let J{a:x128,b:x129}=j64;let J{a:x130,b:x131}=j65;let J{a:x132,b:x133}=j66;let J{a:x134,b:x135}=j67;let J{a:x136,b:x137}=j68;let J{a:x138,b:x139}=j69;let J{a:x140,b:x141}=j70;let J{a:x142,b:x143}=j71;let J{a:x144,b:x145}=j72;let J{a:x146,b:x147}=j73;let J{a:x148,b:x149}=j74;let J{a:x150,b:x151}=j75;let J{a:x152,b:x153}=j76;let J{a:x154,b:x155}=j77;let J{a:x156,b:x157}=j78;let J{a:x158,b:x159}=j79;let J{a:x160,b:x161}=j80;let J{a:x162,b:x163}=j81;let J{a:x164,b:x165}=j82;let J{a:x166,b:x167}=j83;let J{a:x168,b:x169}=j84;let J{a:x170,b:x171}=j85;let J{a:x172,b:x173}=j86;let J{a:x174,b:x175}=j87;let J{a:x176,b:x177}=j88;let J{a:x178,b:x179}=j89;let J{a:x180,b:x181}=j90;let J{a:x182,b:x183}=j91;let J{a:x184,b:x185}=j92;let J{a:x186,b:x187}=j93;let J{a:x188,b:x189}=j94;let J{a:x190,b:x191}=j95;let J{a:x192,b:x193}=j96;let J{a:x194,b:x195}=j97;let J{a:x196,b:x197}=j98;let J{a:x198,b:x199}=j99;let J{a:x200,b:x201}=j100;let J{a:x202,b:x203}=j101;let J{a:x204,b:x205}=j102;let J{a:x206,b:x207}=j103;let J{a:x208,b:x209}=j104;let J{a:x210,b:x211}=j105;let J{a:x212,b:x213}=j106;let J{a:x214,b:x215}=j107;let J{a:x216,b:x217}=j108;let J{a:x218,b:x219}=j109;let J{a:x220,b:x221}=j110;let J{a:x222,b:x223}=j111;let J{a:x224,b:x225}=j112;let J{a:x226,b:x227}=j113;let J{a:x228,b:x229}=j114;let J{a:x230,b:x231}=j115;let J{a:x232,b:x233}=j116;let J{a:x234,b:x235}=j117;let J{a:x236,b:x237}=j118;let J{a:x238,b:x239}=j119;let J{a:x240,b:x241}=j120;let J{a:x242,b:x243}=j121;let J{a:x244,b:x245}=j122;let J{a:x246,b:x247}=j123;let J{a:x248,b:x249}=j124;let J{a:x250,b:x251}=j125;let J{a:x252,b:x253}=j126;let J{a:x254,b:x255}=j127;let J{a:x256,b:x257}=j128;let J{a:x258,b:x259}=j129;let J{a:x260,b:x261}=j130;let J{a:x262,b:x263}=j131;let J{a:x264,b:x265}=j132;let J{a:x266,b:x267}=j133;let J{a:x268,b:x269}=j134;let J{a:x270,b:x271}=j135;let J{a:x272,b:x273}=j136;let J{a:x274,b:x275}=j137;let J{a:x276,b:x277}=j138;let J{a:x278,b:x279}=j139;let J{a:x280,b:x281}=j140;let J{a:x282,b:x283}=j141;let J{a:x284,b:x285}=j142;let J{a:x286,b:x287}=j143;let J{a:x288,b:x289}=j144;let J{a:x290,b:x291}=j145;let J{a:x292,b:x293}=j146;let J{a:x294,b:x295}=j147;let J{a:x296,b:x297}=j148;let J{a:x298,b:x299}=j149;let J{a:x300,b:x301}=j150;let J{a:x302,b:x303}=j151;let J{a:x304,b:x305}=j152;let J{a:x306,b:x307}=j153;let J{a:x308,b:x309}=j154;let J{a:x310,b:x311}=j155;let J{a:x312,b:x313}=j156;let J{a:x314,b:x315}=j157;let J{a:x316,b:x317}=j158;let J{a:x318,b:x319}=j159;let J{a:x320,b:x321}=j160;let J{a:x322,b:x323}=j161;let J{a:x324,b:x325}=j162;let J{a:x326,b:x327}=j163;let J{a:x328,b:x329}=j164;let J{a:x330,b:x331}=j165;let J{a:x332,b:x333}=j166;let J{a:x334,b:x335}=j167;let J{a:x336,b:x337}=j168;let J{a:x338,b:x339}=j169;let J{a:x340,b:x341}=j170;let J{a:x342,b:x343}=j171;let J{a:x344,b:x345}=j172;let J{a:x346,b:x347}=j173;let J{a:x348,b:x349}=j174;let J{a:x350,b:x351}=j175;let J{a:x352,b:x353}=j176;let J{a:x354,b:x355}=j177;let J{a:x356,b:x357}=j178;let J{a:x358,b:x359}=j179;let J{a:x360,b:x361}=j180;let J{a:x362,b:x363}=j181;let J{a:x364,b:x365}=j182;let J{a:x366,b:x367}=j183;let J{a:x368,b:x369}=j184;let J{a:x370,b:x371}=j185;let J{a:x372,b:x373}=j186;let J{a:x374,b:x375}=j187;let J{a:x376,b:x377}=j188;let J{a:x378,b:x379}=j189;let J{a:x380,b:x381}=j190;let J{a:x382,b:x383}=j191;let J{a:x384,b:x385}=j192;let J{a:x386,b:x387}=j193;let J{a:x388,b:x389}=j194;let J{a:x390,b:x391}=j195;let J{a:x392,b:x393}=j196;let J{a:x394,b:x395}=j197;let J{a:x396,b:x397}=j198;let J{a:x398,b:x399}=j199;let J{a:x400,b:x401}=j200;let J{a:x402,b:x403}=j201;let J{a:x404,b:x405}=j202;let J{a:x406,b:x407}=j203;let J{a:x408,b:x409}=j204;let J{a:x410,b:x411}=j205;let J{a:x412,b:x413}=j206;let J{a:x414,b:x415}=j207;let J{a:x416,b:x417}=j208;let J{a:x418,b:x419}=j209;let J{a:x420,b:x421}=j210;let J{a:x422,b:x423}=j211;let J{a:x424,b:x425}=j212;let J{a:x426,b:x427}=j213;let J{a:x428,b:x429}=j214;let J{a:x430,b:x431}=j215;let J{a:x432,b:x433}=j216;let J{a:x434,b:x435}=j217;let J{a:x436,b:x437}=j218;let J{a:x438,b:x439}=j219;let J{a:x440,b:x441}=j220;let J{a:x442,b:x443}=j221;let J{a:x444,b:x445}=j222;let J{a:x446,b:x447}=j223;let J{a:x448,b:x449}=j224;let J{a:x450,b:x451}=j225;let J{a:x452,b:x453}=j226;let J{a:x454,b:x455}=j227;let J{a:x456,b:x457}=j228;let J{a:x458,b:x459}=j229;let J{a:x460,b:x461}=j230;let J{a:x462,b:x463}=j231;let J{a:x464,b:x465}=j232;let J{a:x466,b:x467}=j233;let J{a:x468,b:x469}=j234;let J{a:x470,b:x471}=j235;let J{a:x472,b:x473}=j236;let J{a:x474,b:x475}=j237;let J{a:x476,b:x477}=j238;let J{a:x478,b:x479}=j239;let J{a:x480,b:x481}=j240;let J{a:x482,b:x483}=j241;let J{a:x484,b:x485}=j242;let J{a:x486,b:x487}=j243;let J{a:x488,b:x489}=j244;let J{a:x490,b:x491}=j245;let J{a:x492,b:x493}=j246;let J{a:x494,b:x495}=j247;let J{a:x496,b:x497}=j248;let J{a:x498,b:x499}=j249;let J{a:x500,b:x501}=j250;let J{a:x502,b:x503}=j251;let J{a:x504,b:x505}=j252;let J{a:x506,b:x507}=j253;let J{a:x508,b:x509}=j254;let J{a:x510,b:x511}=j255;
    let c0=[x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16,x17,x18,x19,x20,x21,x22,x23,x24,x25,x26,x27,x28,x29,x30,x31,x32,x33,x34,x35,x36,x37,x38,x39,x40,x41,x42,x43,x44,x45,x46,x47,x48,x49,x50,x51,x52,x53,x54,x55,x56,x57,x58,x59,x60,x61,x62,x63,x64,x65,x66,x67,x68,x69,x70,x71,x72,x73,x74,x75,x76,x77,x78,x79,x80,x81,x82,x83,x84,x85,x86,x87,x88,x89,x90,x91,x92,x93,x94,x95,x96,x97,x98,x99,x100,x101,x102,x103,x104,x105,x106,x107,x108,x109,x110,x111,x112,x113,x114,x115,x116,x117,x118,x119,x120,x121,x122,x123,x124,x125];
    let c1=[x126,x127,x128,x129,x130,x131,x132,x133,x134,x135,x136,x137,x138,x139,x140,x141,x142,x143,x144,x145,x146,x147,x148,x149,x150,x151,x152,x153,x154,x155,x156,x157,x158,x159,x160,x161,x162,x163,x164,x165,x166,x167,x168,x169,x170,x171,x172,x173,x174,x175,x176,x177,x178,x179,x180,x181,x182,x183,x184,x185,x186,x187,x188,x189,x190,x191,x192,x193,x194,x195,x196,x197,x198,x199,x200,x201,x202,x203,x204,x205,x206,x207,x208,x209,x210,x211,x212,x213,x214,x215,x216,x217,x218,x219,x220,x221,x222,x223,x224,x225,x226,x227,x228,x229,x230,x231,x232,x233,x234,x235,x236,x237,x238,x239,x240,x241,x242,x243,x244,x245,x246,x247,x248,x249,x250,x251];
    let c2=[x252,x253,x254,x255,x256,x257,x258,x259,x260,x261,x262,x263,x264,x265,x266,x267,x268,x269,x270,x271,x272,x273,x274,x275,x276,x277,x278,x279,x280,x281,x282,x283,x284,x285,x286,x287,x288,x289,x290,x291,x292,x293,x294,x295,x296,x297,x298,x299,x300,x301,x302,x303,x304,x305,x306,x307,x308,x309,x310,x311,x312,x313,x314,x315,x316,x317,x318,x319,x320,x321,x322,x323,x324,x325,x326,x327,x328,x329,x330,x331,x332,x333,x334,x335,x336,x337,x338,x339,x340,x341,x342,x343,x344,x345,x346,x347,x348,x349,x350,x351,x352,x353,x354,x355,x356,x357,x358,x359,x360,x361,x362,x363,x364,x365,x366,x367,x368,x369,x370,x371,x372,x373,x374,x375,x376,x377];
    let c3=[x378,x379,x380,x381,x382,x383,x384,x385,x386,x387,x388,x389,x390,x391,x392,x393,x394,x395,x396,x397,x398,x399,x400,x401,x402,x403,x404,x405,x406,x407,x408,x409,x410,x411,x412,x413,x414,x415,x416,x417,x418,x419,x420,x421,x422,x423,x424,x425,x426,x427,x428,x429,x430,x431,x432,x433,x434,x435,x436,x437,x438,x439,x440,x441,x442,x443,x444,x445,x446,x447,x448,x449,x450,x451,x452,x453,x454,x455,x456,x457,x458,x459,x460,x461,x462,x463,x464,x465,x466,x467,x468,x469,x470,x471,x472,x473,x474,x475,x476,x477,x478,x479,x480,x481,x482,x483,x484,x485,x486,x487,x488,x489,x490,x491,x492,x493,x494,x495,x496,x497,x498,x499,x500,x501,x502,x503];
    let tail = [x504, x505, x506, x507, x508, x509, x510, x511];
    let (main, tail) = typed_ntt([c0, c1, c2, c3], tail);
    let [g0, g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12, g13, g14, g15, g16, g17, g18, g19, g20, g21, g22, g23, g24, g25, g26, g27] = main;
    let main: [pqbench_ntt_f1024_pf_record::F; 7] = [pqbench_ntt_f1024_pf_record::F { a: g0, b: g1, c: g2, d: g3 }, pqbench_ntt_f1024_pf_record::F { a: g4, b: g5, c: g6, d: g7 }, pqbench_ntt_f1024_pf_record::F { a: g8, b: g9, c: g10, d: g11 }, pqbench_ntt_f1024_pf_record::F { a: g12, b: g13, c: g14, d: g15 }, pqbench_ntt_f1024_pf_record::F { a: g16, b: g17, c: g18, d: g19 }, pqbench_ntt_f1024_pf_record::F { a: g20, b: g21, c: g22, d: g23 }, pqbench_ntt_f1024_pf_record::F { a: g24, b: g25, c: g26, d: g27 }];
    (main.span(), tail)
}

/// An output word: (NTT(s1) + BIAS) + 2^123 * (BIAS - NTT(hint)).
type Lane = BoundedInt<0, 0x7ffffffffffffffffffffffffffffff>;
type LaneBase = UnitInt<0x8000000000000000000000000000000>;
pub(crate) impl SplitWord of DivRemHelper<Wv, LaneBase> {
    type DivT = Lane;
    type RemT = Lane;
}
#[inline(always)]
pub(crate) fn lane_base() -> NonZero<LaneBase> {
    0x8000000000000000000000000000000
}

type ZqT = BoundedInt<0, 12288>;
impl LaneModQ of DivRemHelper<Lane, UnitInt<12289>> {
    type DivT = BoundedInt<0, 865312390453196108977984903754801>;
    type RemT = ZqT;
}
const NQ: NonZero<UnitInt<12289>> = 12289;

/// x * q^-1 for 0 <= x < 2^138: below 2^128 exactly when q divides x.
#[inline(always)]
pub(crate) fn div_ok(x: felt252) -> bool {
    match pqbench_ntt_f1024_pf_record::ci::integer::u128s_from_felt252(x * Q_INV) {
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Narrow(_) => true,
        pqbench_ntt_f1024_pf_record::ci::integer::U128sFromFelt252Result::Wide(_) => false,
    }
}

/// Coordinates 2i and 2i+1 of the 1024-point NTTs, from coordinate i of both halves:
#[inline(always)]
pub(crate) fn pair(w: felt252, we: Word, wo: Word, h0: felt252, h1: felt252, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> bool {
    let (x, y) = pair_v(w, we, wo, h0, h1, dv, nq);
    div_ok(x) && div_ok(y)
}

/// pair's two checked values (multiples of q when valid).
#[inline(always)]
pub(crate) fn pair_v(w: felt252, we: Word, wo: Word, h0: felt252, h1: felt252, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> (felt252, felt252) {
    let (ce, ae) = bounded_int::div_rem(we.v, dv);
    let (co, ao) = bounded_int::div_rem(wo.v, dv);
    let (_, ao) = bounded_int::div_rem(ao, nq);
    let ae: felt252 = upcast(ae);
    let ce: felt252 = upcast(ce);
    let ao: felt252 = upcast(ao);
    let co: felt252 = upcast(co);
    let t1 = ao * w;
    let t2 = co * w;
    ((ae + t1) * h0 + ce + t2, (ae - t1) * h1 + ce - t2 + QL)
}

/// q * 2^123: a multiple of q above every w * c + w * (a mod q) * h.
const QL: felt252 = 0x18008000000000000000000000000000000;

#[inline(always)]
fn trio(
    e: [Word; 3], o: [Word; 3], w: pqbench_ntt_f1024_pf_record::R, hh: [felt252; 6], dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>,
) -> bool {
    let [e0, _, _] = e;
    let [o0, _, _] = o;
    let [h0, h1, _, _, _, _] = hh;
    pair(w.a.into(), e0, o0, h0, h1, dv, nq) && {
        let [_, e1, e2] = e;
        let [_, o1, o2] = o;
        let pqbench_ntt_f1024_pf_record::R { a: _, b: w1, c: w2 } = w;
        let [_, _, h2, h3, h4, h5] = hh;
        pair(w1.into(), e1, o1, h2, h3, dv, nq) && pair(w2.into(), e2, o2, h4, h5, dv, nq)
    }
}

/// One group: 18 roots, h's 36 coordinates from two key felts.
#[inline(always)]
fn group(e: [[Word; 3]; 6], o: [[Word; 3]; 6], fa: (u128, u128), fb: (u128, u128), r: pqbench_ntt_f1024_pf_record::S, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> bool {
    let (ah, al) = match crate::packing::k9(fa) { Some(t) => t, None => { return false; } };
    let ha = match crate::packing::h9(al, nq) { Some(t) => t, None => { return false; } };
    let [e0, e1, e2, e3, e4, e5] = e;
    let [o0, o1, o2, o3, o4, o5] = o;
    let pqbench_ntt_f1024_pf_record::S { s0: t0, s1: t1, s2: t2, s3: t3, s4: t4, s5: t5, s6: t6, s7: t7, s8: t8, s9: t9, s10: t10, s11: t11, s12: t12, s13: t13, s14: t14, s15: t15, s16: t16, s17: t17 } = r; let r0 = pqbench_ntt_f1024_pf_record::R { a: t0, b: t1, c: t2 }; let r1 = pqbench_ntt_f1024_pf_record::R { a: t3, b: t4, c: t5 }; let r2 = pqbench_ntt_f1024_pf_record::R { a: t6, b: t7, c: t8 }; let r3 = pqbench_ntt_f1024_pf_record::R { a: t9, b: t10, c: t11 }; let r4 = pqbench_ntt_f1024_pf_record::R { a: t12, b: t13, c: t14 }; let r5 = pqbench_ntt_f1024_pf_record::R { a: t15, b: t16, c: t17 };
    let (h0, h1, h2, h3, h4, h5, h6, h7, h8) = ha;
    trio(e0, o0, r0, [h0, h1, h2, h3, h4, h5], dv, nq) && {
        let (h9, h10, h11, h12, h13, h14, h15, h16, h17) = crate::packing::h9p(ah, nq);
        trio(e1, o1, r1, [h6, h7, h8, h9, h10, h11], dv, nq) && trio(e2, o2, r2, [h12, h13, h14, h15, h16, h17], dv, nq)
    } && {
        let (bh, bl) = match crate::packing::k9(fb) { Some(t) => t, None => { return false; } };
        let hc = match crate::packing::h9(bl, nq) { Some(t) => t, None => { return false; } };
        let (h18, h19, h20, h21, h22, h23, h24, h25, h26) = hc;
        trio(e3, o3, r3, [h18, h19, h20, h21, h22, h23], dv, nq) && {
            let (h27, h28, h29, h30, h31, h32, h33, h34, h35) = crate::packing::h9p(bh, nq);
            trio(e4, o4, r4, [h24, h25, h26, h27, h28, h29], dv, nq) && trio(e5, o5, r5, [h30, h31, h32, h33, h34, h35], dv, nq)
        }
    }
}

/// A key felt's halves, a zero high half for a felt below 2^128 (cold routes only).
#[inline(always)]
fn ksplit(f: felt252) -> Option<(crate::packing::P9, u128)> {
    let x = match crate::packing::ufs(f) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(l) => (0, l) };
    crate::packing::k9(x)
}
/// A key felt's two halves below q^9, low half first, for any felt (cold).
#[inline(never)]
fn kc(f: felt252) -> Option<(crate::packing::P9, crate::packing::P9)> {
    let (h, l) = ksplit(f)?;
    let (l, _) = crate::packing::k9((l, 0))?;
    Some((l, h))
}
#[inline(never)]
fn trio_c(e: [Word; 3], o: [Word; 3], w: pqbench_ntt_f1024_pf_record::R, hh: [felt252; 6], dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> bool {
    let [e0, e1, e2] = e;
    let [o0, o1, o2] = o;
    let pqbench_ntt_f1024_pf_record::R { a: w0, b: w1, c: w2 } = w;
    let [h0, h1, h2, h3, h4, h5] = hh;
    pair_c(w0.into(), e0, o0, h0, h1, dv, nq) & pair_c(w1.into(), e1, o1, h2, h3, dv, nq) & pair_c(w2.into(), e2, o2, h4, h5, dv, nq)
}
/// pair, out of line (cold).
#[inline(never)]
fn pair_c(w: felt252, we: Word, wo: Word, h0: felt252, h1: felt252, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> bool {
    pair(w, we, wo, h0, h1, dv, nq)
}
/// One group for any two key felts, every pair checked (cold).
#[inline(never)]
fn group_c(e: [[Word; 3]; 6], o: [[Word; 3]; 6], fa: felt252, fb: felt252, r: pqbench_ntt_f1024_pf_record::S, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> bool {
    let (la, ha) = match kc(fa) { Some(t) => t, None => { return false; } };
    let (lb, hb) = match kc(fb) { Some(t) => t, None => { return false; } };
    let ([h0, h1, h2, h3, h4, h5, h6, h7, h8], [h9, h10, h11, h12, h13, h14, h15, h16, h17]) = crate::packing::dec18(la, ha, nq);
    let ([h18, h19, h20, h21, h22, h23, h24, h25, h26], [h27, h28, h29, h30, h31, h32, h33, h34, h35]) = crate::packing::dec18(lb, hb, nq);
    let [e0, e1, e2, e3, e4, e5] = e;
    let [o0, o1, o2, o3, o4, o5] = o;
    let pqbench_ntt_f1024_pf_record::S { s0: t0, s1: t1, s2: t2, s3: t3, s4: t4, s5: t5, s6: t6, s7: t7, s8: t8, s9: t9, s10: t10, s11: t11, s12: t12, s13: t13, s14: t14, s15: t15, s16: t16, s17: t17 } = r; let r0 = pqbench_ntt_f1024_pf_record::R { a: t0, b: t1, c: t2 }; let r1 = pqbench_ntt_f1024_pf_record::R { a: t3, b: t4, c: t5 }; let r2 = pqbench_ntt_f1024_pf_record::R { a: t6, b: t7, c: t8 }; let r3 = pqbench_ntt_f1024_pf_record::R { a: t9, b: t10, c: t11 }; let r4 = pqbench_ntt_f1024_pf_record::R { a: t12, b: t13, c: t14 }; let r5 = pqbench_ntt_f1024_pf_record::R { a: t15, b: t16, c: t17 };
    trio_c(e0, o0, r0, [upcast(h0), upcast(h1), upcast(h2), upcast(h3), upcast(h4), upcast(h5)], dv, nq) & trio_c(e1, o1, r1, [upcast(h6), upcast(h7), upcast(h8), upcast(h9), upcast(h10), upcast(h11)], dv, nq)
        & trio_c(e2, o2, r2, [upcast(h12), upcast(h13), upcast(h14), upcast(h15), upcast(h16), upcast(h17)], dv, nq) & trio_c(e3, o3, r3, [upcast(h18), upcast(h19), upcast(h20), upcast(h21), upcast(h22), upcast(h23)], dv, nq)
        & trio_c(e4, o4, r4, [upcast(h24), upcast(h25), upcast(h26), upcast(h27), upcast(h28), upcast(h29)], dv, nq) & trio_c(e5, o5, r5, [upcast(h30), upcast(h31), upcast(h32), upcast(h33), upcast(h34), upcast(h35)], dv, nq)
}

/// gb for a group of key felts with a narrow felt (cold): the same pops, tolerant splits.
#[inline(never)]
fn gbt(t: GS) -> GS {
    match core::gas::withdraw_gas() { Some(_) => {}, None => { return failed(); } }
    let (me, mo, pk, ws, dv, nq, _, _) = t;
    let mut es = me;
    let mut os = mo;
    let mut pk = pk;
    let mut ws = ws;
    let Some(eb) = es.pop_front() else { return failed(); };
    let pqbench_ntt_f1024_pf_record::F { a: e0, b: e1, c: e2, d: e3 } = *eb;
    let Some(ob) = os.pop_front() else { return failed(); };
    let pqbench_ntt_f1024_pf_record::F { a: o0, b: o1, c: o2, d: o3 } = *ob;
    let Some(fb) = pk.multi_pop_front::<8>() else { return failed(); };
    let Some(wb) = ws.pop_front() else { return failed(); };
    let pqbench_ntt_f1024_pf_record::Q { a: g0, b: g1, c: g2, d: g3 } = *wb;
    let [f0, f1, f2, f3, f4, f5, f6, f7] = (*fb).unbox();
    if !(group_c(e0.g, o0.g, f0, f1, g0, dv, nq) & group_c(e1.g, o1.g, f2, f3, g1, dv, nq) & group_c(e2.g, o2.g, f4, f5, g2, dv, nq)
        & group_c(e3.g, o3.g, f6, f7, g3, dv, nq)) {
        return failed();
    }
    // every pair is checked: (0, 0) passes the next div_ok
    (es, os, pk, ws, dv, nq, 0, 0)
}
/// group, its last pair's two values returned for the next call to check.
#[inline(always)]
fn group_v(e: [[Word; 3]; 6], o: [[Word; 3]; 6], fa: (u128, u128), fb: (u128, u128), r: pqbench_ntt_f1024_pf_record::S, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>) -> Option<(felt252, felt252)> {
    let (ah, al) = crate::packing::k9(fa)?;
    let ha = crate::packing::h9(al, nq)?;
    let [e0, e1, e2, e3, e4, e5] = e;
    let [o0, o1, o2, o3, o4, o5] = o;
    let pqbench_ntt_f1024_pf_record::S { s0: t0, s1: t1, s2: t2, s3: t3, s4: t4, s5: t5, s6: t6, s7: t7, s8: t8, s9: t9, s10: t10, s11: t11, s12: t12, s13: t13, s14: t14, s15: t15, s16: t16, s17: t17 } = r; let r0 = pqbench_ntt_f1024_pf_record::R { a: t0, b: t1, c: t2 }; let r1 = pqbench_ntt_f1024_pf_record::R { a: t3, b: t4, c: t5 }; let r2 = pqbench_ntt_f1024_pf_record::R { a: t6, b: t7, c: t8 }; let r3 = pqbench_ntt_f1024_pf_record::R { a: t9, b: t10, c: t11 }; let r4 = pqbench_ntt_f1024_pf_record::R { a: t12, b: t13, c: t14 }; let r5 = pqbench_ntt_f1024_pf_record::R { a: t15, b: t16, c: t17 };
    let (h0, h1, h2, h3, h4, h5, h6, h7, h8) = ha;
    if !trio(e0, o0, r0, [h0, h1, h2, h3, h4, h5], dv, nq) {
        return None;
    }
    let (h9, h10, h11, h12, h13, h14, h15, h16, h17) = crate::packing::h9p(ah, nq);
    if !(trio(e1, o1, r1, [h6, h7, h8, h9, h10, h11], dv, nq) && trio(e2, o2, r2, [h12, h13, h14, h15, h16, h17], dv, nq)) {
        return None;
    }
    let (bh, bl) = crate::packing::k9(fb)?;
    let (h18, h19, h20, h21, h22, h23, h24, h25, h26) = crate::packing::h9(bl, nq)?;
    if !trio(e3, o3, r3, [h18, h19, h20, h21, h22, h23], dv, nq) {
        return None;
    }
    let (h27, h28, h29, h30, h31, h32, h33, h34, h35) = crate::packing::h9p(bh, nq);
    if !trio(e4, o4, r4, [h24, h25, h26, h27, h28, h29], dv, nq) {
        return None;
    }
    let [x0, x1, x2] = e5;
    let [y0, y1, y2] = o5;
    let pqbench_ntt_f1024_pf_record::R { a: w0, b: w1, c: w2 } = r5;
    if !(pair(w0.into(), x0, y0, h30, h31, dv, nq) && pair(w1.into(), x1, y1, h32, h33, dv, nq)) {
        return None;
    }
    Some(pair_v(w2.into(), x2, y2, h34, h35, dv, nq))
}

#[inline(never)]
/// `pk`: 57 felts of 18 base-q digits of h (9 per u128 half).
pub(crate) fn merge_check(
    o: (Span<pqbench_ntt_f1024_pf_record::F>, [Word; 8]), e: (Span<pqbench_ntt_f1024_pf_record::F>, [Word; 8]), pk: Span<felt252>, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>,
) -> GS {
    let (mo, to) = o;
    let (me, te) = e;
    let mut pt = pk;
    let [e0, e1, e2, e3, e4, e5, e6, e7] = te;
    let [o0, o1, o2, o3, o4, o5, o6, o7] = to;
    let [w0, w1, w2, w3, w4, w5, w6, w7] = crate::ntt::ROOTS_T;
    let Some(lf) = pt.pop_back() else { return failed(); };
    let (lh, ll) = match crate::packing::hi7w(*lf) {
        crate::packing::H7::Ok(t) => t,
        crate::packing::H7::Narrow(l) => { return merge_check_n(o, e, pk, l, dv, nq); },
        crate::packing::H7::Bad => { return failed(); },
    };
    let (h0, h1, h2, h3, h4, h5, h6, h7, h8) = match crate::packing::h9(ll, nq) { Some(t) => t, None => { return failed(); } };
    let (h9, h10, h11, h12, h13, h14, h15) = crate::packing::h7p(lh, nq);
    if !(pair(w0.into(), e0, o0, h0, h1, dv, nq) && pair(w1.into(), e1, o1, h2, h3, dv, nq) && pair(w2.into(), e2, o2, h4, h5, dv, nq)
        && pair(w3.into(), e3, o3, h6, h7, dv, nq) && pair(w4.into(), e4, o4, h8, h9, dv, nq)
        && pair(w5.into(), e5, o5, h10, h11, dv, nq) && pair(w6.into(), e6, o6, h12, h13, dv, nq)
    ) {
        return failed();
    }
    let (u, v) = pair_v(w7.into(), e7, o7, h14, h15, dv, nq);
    gw(gw(gw(gw(gw(gw(gw((me, mo, pk, crate::ntt::ROOTS_G.span(), dv, nq, u, v))))))))
}

#[inline(never)]
/// merge_check for a narrow last key felt (cold).
fn merge_check_n(
    o: (Span<pqbench_ntt_f1024_pf_record::F>, [Word; 8]), e: (Span<pqbench_ntt_f1024_pf_record::F>, [Word; 8]), pk: Span<felt252>, ll: u128, dv: NonZero<LaneBase>, nq: NonZero<UnitInt<12289>>,
) -> GS {
    let (mo, to) = o;
    let (me, te) = e;
    let [e0, e1, e2, e3, e4, e5, e6, e7] = te;
    let [o0, o1, o2, o3, o4, o5, o6, o7] = to;
    let [w0, w1, w2, w3, w4, w5, w6, w7] = crate::ntt::ROOTS_T;
    // ll: the narrow last key felt; its high half (seven digits h9..h15) is zero
    if let Some(x) = crate::packing::p9(ll) {
        let ([h0, h1, h2, h3, h4, h5, h6, h7, h8], _) = crate::packing::dec18(x, x, nq);
        if trio_c([e0, e1, e2], [o0, o1, o2], pqbench_ntt_f1024_pf_record::R { a: w0, b: w1, c: w2 }, [upcast(h0), upcast(h1), upcast(h2), upcast(h3), upcast(h4), upcast(h5)], dv, nq)
            & trio_c([e3, e4, e5], [o3, o4, o5], pqbench_ntt_f1024_pf_record::R { a: w3, b: w4, c: w5 }, [upcast(h6), upcast(h7), upcast(h8), 0, 0, 0], dv, nq)
            & pair_c(w6.into(), e6, o6, 0, 0, dv, nq) & pair_c(w7.into(), e7, o7, 0, 0, dv, nq) {
            // every pair is checked: (0, 0) passes the next div_ok
            return gw(gw(gw(gw(gw(gw(gw((me, mo, pk, crate::ntt::ROOTS_G.span(), dv, nq, 0, 0))))))));
        }
    }
    failed()
}

/// The state of a failed check: empty spans and pending values (0, 1), which div_ok rejects.
#[inline(always)]
fn failed() -> GS {
    (array![].span(), array![].span(), array![].span(), array![].span(), lane_base(), NQ, 0, 1)
}

/// The merge check's state between group calls.
type GS = (Span<pqbench_ntt_f1024_pf_record::F>, Span<pqbench_ntt_f1024_pf_record::F>, Span<felt252>, Span<pqbench_ntt_f1024_pf_record::Q>, NonZero<LaneBase>, NonZero<UnitInt<12289>>, felt252, felt252);

/// Four groups of the 1024-point check as a call without gas builtin.
#[inline(never)]
fn gw(t: GS) -> GS {
    core::internal::revoke_ap_tracking();
    gb(t)
}

/// The state after the pending pair and four groups, or None on a failed check.
#[inline(always)]
fn gb(t: GS) -> GS {
    let (me, mo, pk, ws, dv, nq, u, v) = t;
    if !(div_ok(u) && div_ok(v)) {
        return failed();
    }
    let mut es = me;
    let mut os = mo;
    let mut pk = pk;
    let mut ws = ws;
    let Some(eb) = es.pop_front() else { return failed(); };
    let Some(ob) = os.pop_front() else { return failed(); };
    let Some(fb) = pk.multi_pop_front::<8>() else { return failed(); };
    let Some(wb) = ws.pop_front() else { return failed(); };
    let [f0, f1, f2, f3, f4, f5, f6, f7] = (*fb).unbox();
    let p0 = match crate::packing::ufs(f0) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p1 = match crate::packing::ufs(f1) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p2 = match crate::packing::ufs(f2) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p3 = match crate::packing::ufs(f3) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p4 = match crate::packing::ufs(f4) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p5 = match crate::packing::ufs(f5) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p6 = match crate::packing::ufs(f6) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    let p7 = match crate::packing::ufs(f7) { crate::packing::UR::Wide(x) => x, crate::packing::UR::Narrow(_) => { return gbt(t); } };
    if !group((*eb).a.g, (*ob).a.g, p0, p1, (*wb).a, dv, nq) {
        return failed();
    }
    if !group((*eb).b.g, (*ob).b.g, p2, p3, (*wb).b, dv, nq) {
        return failed();
    }
    if !group((*eb).c.g, (*ob).c.g, p4, p5, (*wb).c, dv, nq) {
        return failed();
    }
    let (u, v) = match group_v((*eb).d.g, (*ob).d.g, p6, p7, (*wb).d, dv, nq) { Some(t) => t, None => { return failed(); } };
    (es, os, pk, ws, dv, nq, u, v)
}

#[inline(always)]
pub(crate) fn csq_diff(p: felt252, k: felt252) -> felt252 {
    let x = p - k;
    let a: Option<u128> = (x + 6144).try_into();
    match a {
        Option::Some(au) => {
            if au <= 12288 {
                x * x
            } else {
                let c = x - 12289;
                c * c
            }
        },
        Option::None => {
            let c = x + 12289;
            c * c
        },
    }
}
