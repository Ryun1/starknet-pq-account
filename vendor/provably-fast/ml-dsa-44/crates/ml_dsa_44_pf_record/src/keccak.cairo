//! SHAKE-128 and SHAKE-256 (FIPS 202) for ML-DSA, on the Keccak-f[1600] permutation from
//! OpenZeppelin's Falcon-512 crate (crates/falcon_512/src/hashing/shake256.cairo), copied here so
//! this crate stands alone. `absorb` takes a whole input with SHAKE's padding; `squeeze` reads a
//! block of output, and a sampler that needs more permutes the state for the next block.

const MASK64: u128 = 0xffffffffffffffff;

/// Keccak-f[1600] round constants (FIPS 202, Table 1).
const ROUND_CONSTANTS: [u128; 24] = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
];

/// Rotate a 64-bit lane left, given `pow = 2^r` with 0 < r < 64. The widened felt
/// product `x * 2^r < 2^127` splits at bit 64 into the bits that stay (`lo`) and the
/// bits that wrap to the bottom (`hi`); they occupy disjoint positions, so `lo + hi`
/// is the rotation.
#[inline(always)]
fn rotl(x: u128, pow: felt252, two64: NonZero<u128>) -> u128 {
    let wide: u128 = (x.into() * pow).try_into().unwrap();
    let (hi, lo) = DivRem::div_rem(wide, two64);
    lo + hi
}

/// Keccak-f[1600]: 24 rounds of θ, ρ, π, χ, ι on the 25-lane state, fully unrolled
/// over lane locals. The ρ+π terms read `b[dst] = rotl(a[src] ^ d[src mod 5], ρ[dst])`
/// with the π source indices and ρ offsets from FIPS 202, precomposed per destination.
pub fn keccak_f1600(state: [u128; 25]) -> [u128; 25] {
    let two64: NonZero<u128> = 0x10000000000000000_u128.try_into().unwrap();
    let mut s = state;
    for rc in ROUND_CONSTANTS.span() {
        let rc = *rc;
        let [
            s00,
            s01,
            s02,
            s03,
            s04,
            s05,
            s06,
            s07,
            s08,
            s09,
            s10,
            s11,
            s12,
            s13,
            s14,
            s15,
            s16,
            s17,
            s18,
            s19,
            s20,
            s21,
            s22,
            s23,
            s24,
        ] =
            s;

        // theta: column parities and the per-column mixing term d[x] = c[x-1] ^ rotl(c[x+1], 1).
        let c0 = s00 ^ s05 ^ s10 ^ s15 ^ s20;
        let c1 = s01 ^ s06 ^ s11 ^ s16 ^ s21;
        let c2 = s02 ^ s07 ^ s12 ^ s17 ^ s22;
        let c3 = s03 ^ s08 ^ s13 ^ s18 ^ s23;
        let c4 = s04 ^ s09 ^ s14 ^ s19 ^ s24;
        let d0 = c4 ^ rotl(c1, 0x2, two64);
        let d1 = c0 ^ rotl(c2, 0x2, two64);
        let d2 = c1 ^ rotl(c3, 0x2, two64);
        let d3 = c2 ^ rotl(c4, 0x2, two64);
        let d4 = c3 ^ rotl(c0, 0x2, two64);

        // theta (fused) + rho + pi, straight into destination order.
        let b00 = s00 ^ d0;
        let b01 = rotl(s06 ^ d1, 0x100000000000, two64);
        let b02 = rotl(s12 ^ d2, 0x80000000000, two64);
        let b03 = rotl(s18 ^ d3, 0x200000, two64);
        let b04 = rotl(s24 ^ d4, 0x4000, two64);
        let b05 = rotl(s03 ^ d3, 0x10000000, two64);
        let b06 = rotl(s09 ^ d4, 0x100000, two64);
        let b07 = rotl(s10 ^ d0, 0x8, two64);
        let b08 = rotl(s16 ^ d1, 0x200000000000, two64);
        let b09 = rotl(s22 ^ d2, 0x2000000000000000, two64);
        let b10 = rotl(s01 ^ d1, 0x2, two64);
        let b11 = rotl(s07 ^ d2, 0x40, two64);
        let b12 = rotl(s13 ^ d3, 0x2000000, two64);
        let b13 = rotl(s19 ^ d4, 0x100, two64);
        let b14 = rotl(s20 ^ d0, 0x40000, two64);
        let b15 = rotl(s04 ^ d4, 0x8000000, two64);
        let b16 = rotl(s05 ^ d0, 0x1000000000, two64);
        let b17 = rotl(s11 ^ d1, 0x400, two64);
        let b18 = rotl(s17 ^ d2, 0x8000, two64);
        let b19 = rotl(s23 ^ d3, 0x100000000000000, two64);
        let b20 = rotl(s02 ^ d2, 0x4000000000000000, two64);
        let b21 = rotl(s08 ^ d3, 0x80000000000000, two64);
        let b22 = rotl(s14 ^ d4, 0x8000000000, two64);
        let b23 = rotl(s15 ^ d0, 0x20000000000, two64);
        let b24 = rotl(s21 ^ d1, 0x4, two64);

        // chi (complement as MASK64 - b), with iota folded into lane 0.
        s =
            [
                b00 ^ ((MASK64 - b01) & b02) ^ rc, b01 ^ ((MASK64 - b02) & b03),
                b02 ^ ((MASK64 - b03) & b04), b03 ^ ((MASK64 - b04) & b00),
                b04 ^ ((MASK64 - b00) & b01), b05 ^ ((MASK64 - b06) & b07),
                b06 ^ ((MASK64 - b07) & b08), b07 ^ ((MASK64 - b08) & b09),
                b08 ^ ((MASK64 - b09) & b05), b09 ^ ((MASK64 - b05) & b06),
                b10 ^ ((MASK64 - b11) & b12), b11 ^ ((MASK64 - b12) & b13),
                b12 ^ ((MASK64 - b13) & b14), b13 ^ ((MASK64 - b14) & b10),
                b14 ^ ((MASK64 - b10) & b11), b15 ^ ((MASK64 - b16) & b17),
                b16 ^ ((MASK64 - b17) & b18), b17 ^ ((MASK64 - b18) & b19),
                b18 ^ ((MASK64 - b19) & b15), b19 ^ ((MASK64 - b15) & b16),
                b20 ^ ((MASK64 - b21) & b22), b21 ^ ((MASK64 - b22) & b23),
                b22 ^ ((MASK64 - b23) & b24), b23 ^ ((MASK64 - b24) & b20),
                b24 ^ ((MASK64 - b20) & b21),
            ];
    }
    s
}

/// SHAKE-128's rate: 168 bytes (21 lanes).
pub const SHAKE128_RATE: u32 = 168;
/// SHAKE-256's rate: 136 bytes (17 lanes).
pub const SHAKE256_RATE: u32 = 136;

/// The state after absorbing `input` at `rate` bytes, padded with SHAKE's domain bits 0x1F,
/// zeros, and 0x80 in the block's last byte (pad10*1).
pub fn absorb(input: Span<u8>, rate: u32) -> [u128; 25] {
    let lanes = rate / 8;
    let mut state = [0_u128; 25];
    let mut rest = input;
    while rest.len() >= rate {
        state = keccak_f1600(xor_block(state, rest.slice(0, rate), lanes));
        rest = rest.slice(rate, rest.len() - rate);
    }
    let mut last: Array<u8> = array![];
    last.append_span(rest);
    if last.len() == rate - 1 {
        last.append(0x9f);
    } else {
        last.append(0x1f);
        while last.len() != rate - 1 {
            last.append(0);
        }
        last.append(0x80);
    }
    keccak_f1600(xor_block(state, last.span(), lanes))
}

/// The first `lanes` lanes of the state as bytes, each lane little-endian: a block of output.
pub fn squeeze(state: [u128; 25], lanes: u32) -> Array<u8> {
    let byte: NonZero<u128> = 256_u128.try_into().unwrap();
    let mut out: Array<u8> = array![];
    let mut lane = 0;
    for s in state.span() {
        if lane == lanes {
            break;
        }
        let mut rest: u128 = *s;
        let mut k = 0;
        while k != 8 {
            let (above, low) = DivRem::div_rem(rest, byte);
            out.append(low.try_into().unwrap());
            rest = above;
            k += 1;
        }
        lane += 1;
    }
    out
}

/// SHAKE-256 of `input`, `out_bytes` long.
pub fn shake256(input: Span<u8>, out_bytes: u32) -> Array<u8> {
    let mut state = absorb(input, SHAKE256_RATE);
    let mut out: Array<u8> = array![];
    loop {
        let block = squeeze(state, SHAKE256_RATE / 8);
        let take = if out_bytes - out.len() < SHAKE256_RATE {
            out_bytes - out.len()
        } else {
            SHAKE256_RATE
        };
        out.append_span(block.span().slice(0, take));
        if out.len() == out_bytes {
            break;
        }
        state = keccak_f1600(state);
    }
    out
}

/// XOR a block into the state: its first 17 lanes, and 4 more at SHAKE-128's rate.
fn xor_block(state: [u128; 25], block: Span<u8>, lanes: u32) -> [u128; 25] {
    let [
        s0,
        s1,
        s2,
        s3,
        s4,
        s5,
        s6,
        s7,
        s8,
        s9,
        s10,
        s11,
        s12,
        s13,
        s14,
        s15,
        s16,
        s17,
        s18,
        s19,
        s20,
        s21,
        s22,
        s23,
        s24,
    ] =
        state;
    let mut b = block;
    let s0 = s0 ^ lane(ref b);
    let s1 = s1 ^ lane(ref b);
    let s2 = s2 ^ lane(ref b);
    let s3 = s3 ^ lane(ref b);
    let s4 = s4 ^ lane(ref b);
    let s5 = s5 ^ lane(ref b);
    let s6 = s6 ^ lane(ref b);
    let s7 = s7 ^ lane(ref b);
    let s8 = s8 ^ lane(ref b);
    let s9 = s9 ^ lane(ref b);
    let s10 = s10 ^ lane(ref b);
    let s11 = s11 ^ lane(ref b);
    let s12 = s12 ^ lane(ref b);
    let s13 = s13 ^ lane(ref b);
    let s14 = s14 ^ lane(ref b);
    let s15 = s15 ^ lane(ref b);
    let s16 = s16 ^ lane(ref b);
    if lanes == 17 {
        return [
            s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18,
            s19, s20, s21, s22, s23, s24,
        ];
    }
    let s17 = s17 ^ lane(ref b);
    let s18 = s18 ^ lane(ref b);
    let s19 = s19 ^ lane(ref b);
    let s20 = s20 ^ lane(ref b);
    [
        s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19,
        s20, s21, s22, s23, s24,
    ]
}

/// The next 8 bytes as a little-endian lane.
#[inline(always)]
fn lane(ref bytes: Span<u8>) -> u128 {
    let [b0, b1, b2, b3, b4, b5, b6, b7] = (*bytes.multi_pop_front::<8>().unwrap()).unbox();
    let v: felt252 = b0.into()
        + 0x100 * b1.into()
        + 0x10000 * b2.into()
        + 0x1000000 * b3.into()
        + 0x100000000 * b4.into()
        + 0x10000000000 * b5.into()
        + 0x1000000000000 * b6.into()
        + 0x100000000000000 * b7.into();
    v.try_into().unwrap()
}
