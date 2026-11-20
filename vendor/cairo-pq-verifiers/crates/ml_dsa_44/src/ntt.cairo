//! The ring Z_q[X]/(X^256 + 1) with q = 8380417: the NTT and its inverse (FIPS 204, Algorithms 41
//! and 42) and the NTT-domain row product of verification.
//!
//! Polynomials are 256 felt252 values in [0, q) between functions. Inside a transform the
//! butterflies run in felt252 without reducing (one multiplication and two additions each), the
//! way OpenZeppelin's NTT engine does: a subtraction adds `off`, a multiple of q above anything it
//! subtracts, and every four layers a pass reduces the values to [0, q) through u128 division.
//! Four layers keep every value below 2^115 (forward) or 2^119 (inverse), so felt252 never wraps
//! and every reduction input fits u128; ref/lazy_ntt.py derives the offsets and checks the
//! schedule against Algorithms 41 and 42.

pub const Q: u32 = 8380417;
const Q_FELT: felt252 = 8380417;
const Q128: u128 = 8380417;
/// 256^-1 mod q (Algorithm 42's f).
const N_INV: felt252 = 8347681;
/// f * (q - ZETAS[1]) mod q: the last inverse layer's twiddle with f folded in.
const N_INV_ZETA1: felt252 = 46690;
/// q^2: added to a row so that subtracting c * t1 (< q^2) stays non-negative.
const Q_SQUARED: felt252 = 70231389093889;

/// Forward layer k of a group: inputs below B_k (B_0 = q, B_k+1 = B_k (q + 1)), off = q B_k.
const FWD_OFF_0: felt252 = 70231389093889;
const FWD_OFF_1: felt252 = 588568397327431065602;
const FWD_OFF_2: felt252 = 4932449191193955195930181636;
const FWD_OFF_3: felt252 = 41335985985967263615166820925603848;
/// Inverse layer k of a group: inputs below C_k, off the least multiple of q >= C_k - 1.
const INV_OFF_0: felt252 = 8380417;
const INV_OFF_1: felt252 = 140462761426944;
const INV_OFF_2: felt252 = 2354272676301716324353;
const INV_OFF_3: felt252 = 39459568809683448624138141696;

/// ZETAS[k] = 1753^BitRev8(k) mod q (FIPS 204, Appendix B).
const ZETAS: [felt252; 256] = [
    1, 4808194, 3765607, 3761513, 5178923, 5496691, 5234739, 5178987, 7778734, 3542485, 2682288,
    2129892, 3764867, 7375178, 557458, 7159240, 5010068, 4317364, 2663378, 6705802, 4855975,
    7946292, 676590, 7044481, 5152541, 1714295, 2453983, 1460718, 7737789, 4795319, 2815639,
    2283733, 3602218, 3182878, 2740543, 4793971, 5269599, 2101410, 3704823, 1159875, 394148, 928749,
    1095468, 4874037, 2071829, 4361428, 3241972, 2156050, 3415069, 1759347, 7562881, 4805951,
    3756790, 6444618, 6663429, 4430364, 5483103, 3192354, 556856, 3870317, 2917338, 1853806,
    3345963, 1858416, 3073009, 1277625, 5744944, 3852015, 4183372, 5157610, 5258977, 8106357,
    2508980, 2028118, 1937570, 4564692, 2811291, 5396636, 7270901, 4158088, 1528066, 482649,
    1148858, 5418153, 7814814, 169688, 2462444, 5046034, 4213992, 4892034, 1987814, 5183169,
    1736313, 235407, 5130263, 3258457, 5801164, 1787943, 5989328, 6125690, 3482206, 4197502,
    7080401, 6018354, 7062739, 2461387, 3035980, 621164, 3901472, 7153756, 2925816, 3374250,
    1356448, 5604662, 2683270, 5601629, 4912752, 2312838, 7727142, 7921254, 348812, 8052569,
    1011223, 6026202, 4561790, 6458164, 6143691, 1744507, 1753, 6444997, 5720892, 6924527, 2660408,
    6600190, 8321269, 2772600, 1182243, 87208, 636927, 4415111, 4423672, 6084020, 5095502, 4663471,
    8352605, 822541, 1009365, 5926272, 6400920, 1596822, 4423473, 4620952, 6695264, 4969849,
    2678278, 4611469, 4829411, 635956, 8129971, 5925040, 4234153, 6607829, 2192938, 6653329,
    2387513, 4768667, 8111961, 5199961, 3747250, 2296099, 1239911, 4541938, 3195676, 2642980,
    1254190, 8368000, 2998219, 141835, 8291116, 2513018, 7025525, 613238, 7070156, 6161950, 7921677,
    6458423, 4040196, 4908348, 2039144, 6500539, 7561656, 6201452, 6757063, 2105286, 6006015,
    6346610, 586241, 7200804, 527981, 5637006, 6903432, 1994046, 2491325, 6987258, 507927, 7192532,
    7655613, 6545891, 5346675, 8041997, 2647994, 3009748, 5767564, 4148469, 749577, 4357667,
    3980599, 2569011, 6764887, 1723229, 1665318, 2028038, 1163598, 5011144, 3994671, 8368538,
    7009900, 3020393, 3363542, 214880, 545376, 7609976, 3105558, 7277073, 508145, 7826699, 860144,
    3430436, 140244, 6866265, 6195333, 3123762, 2358373, 6187330, 5365997, 6663603, 2926054,
    7987710, 8077412, 3531229, 4405932, 4606686, 1900052, 7598542, 1054478, 7648983,
];

/// Every value reduced to [0, q); each must be below 2^128.
fn reduce(a: Span<felt252>) -> Array<felt252> {
    let q: NonZero<u128> = Q128.try_into().unwrap();
    let mut out: Array<felt252> = array![];
    for v in a {
        let (_, r) = DivRem::div_rem(TryInto::<felt252, u128>::try_into(*v).unwrap(), q);
        out.append(r.into());
    }
    out
}

/// One forward layer (Algorithm 41's inner loops for one `len`): per block, x + z * y in order,
/// then x + off - z * y.
fn ntt_layer(a: Span<felt252>, len: u32, ref zetas: Span<felt252>, off: felt252) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut start = 0;
    while start != 256 {
        let z = *zetas.pop_front().unwrap();
        let low = a.slice(start, len);
        let high = a.slice(start + len, len);
        let mut x = low;
        let mut y = high;
        while let Some(v) = x.pop_front() {
            out.append(*v + z * *y.pop_front().unwrap());
        }
        let mut x = low;
        let mut y = high;
        while let Some(v) = x.pop_front() {
            out.append(*v + off - z * *y.pop_front().unwrap());
        }
        start += 2 * len;
    }
    out
}

/// Four forward layers from `len` down, then the reduction.
fn ntt_group(a: Span<felt252>, len: u32, ref zetas: Span<felt252>) -> Array<felt252> {
    let a = ntt_layer(a, len, ref zetas, FWD_OFF_0);
    let a = ntt_layer(a.span(), len / 2, ref zetas, FWD_OFF_1);
    let a = ntt_layer(a.span(), len / 4, ref zetas, FWD_OFF_2);
    let a = ntt_layer(a.span(), len / 8, ref zetas, FWD_OFF_3);
    reduce(a.span())
}

/// NTT (Algorithm 41) of a polynomial in [0, q).
pub fn ntt(w: Span<felt252>) -> Array<felt252> {
    let mut zetas = ZETAS.span().slice(1, 255);
    let a = ntt_group(w, 128, ref zetas);
    ntt_group(a.span(), 8, ref zetas)
}

/// One inverse layer (Algorithm 42's inner loops for one `len`, zetas taken from the back): per
/// block, x + y in order, then (q - zeta) * (x + off - y).
fn intt_layer(
    a: Span<felt252>, len: u32, ref zetas: Span<felt252>, off: felt252,
) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut start = 0;
    while start != 256 {
        let z = Q_FELT - *zetas.pop_back().unwrap();
        let low = a.slice(start, len);
        let high = a.slice(start + len, len);
        let mut x = low;
        let mut y = high;
        while let Some(v) = x.pop_front() {
            out.append(*v + *y.pop_front().unwrap());
        }
        let mut x = low;
        let mut y = high;
        while let Some(v) = x.pop_front() {
            out.append(z * (*v + off - *y.pop_front().unwrap()));
        }
        start += 2 * len;
    }
    out
}

/// The last inverse layer (len 128, zeta index 1) with the final multiplication by f folded in.
fn intt_last(a: Span<felt252>, off: felt252) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let low = a.slice(0, 128);
    let high = a.slice(128, 128);
    let mut x = low;
    let mut y = high;
    while let Some(v) = x.pop_front() {
        out.append(N_INV * (*v + *y.pop_front().unwrap()));
    }
    let mut x = low;
    let mut y = high;
    while let Some(v) = x.pop_front() {
        out.append(N_INV_ZETA1 * (*v + off - *y.pop_front().unwrap()));
    }
    out
}

/// Inverse NTT (Algorithm 42) of a polynomial in [0, q).
pub fn intt(w: Span<felt252>) -> Array<felt252> {
    // Zeta indices 255 down to 2; index 1 is folded into the last layer.
    let mut zetas = ZETAS.span().slice(2, 254);
    let a = intt_layer(w, 1, ref zetas, INV_OFF_0);
    let a = intt_layer(a.span(), 2, ref zetas, INV_OFF_1);
    let a = intt_layer(a.span(), 4, ref zetas, INV_OFF_2);
    let a = intt_layer(a.span(), 8, ref zetas, INV_OFF_3);
    let a = reduce(a.span());
    let a = intt_layer(a.span(), 16, ref zetas, INV_OFF_0);
    let a = intt_layer(a.span(), 32, ref zetas, INV_OFF_1);
    let a = intt_layer(a.span(), 64, ref zetas, INV_OFF_2);
    reduce(intt_last(a.span(), INV_OFF_3).span())
}

/// One row of A_hat o z_hat - c_hat o t1_hat (Algorithm 8, step 8, before the inverse NTT),
/// reduced: a[0] z[0] + ... + a[3] z[3] + q^2 - c t < 5 q^2 < 2^49 for inputs in [0, q).
pub fn row(
    a: Span<Span<felt252>>, z: Span<Span<felt252>>, c: Span<felt252>, t: Span<felt252>,
) -> Array<felt252> {
    let mut a0 = *a.at(0);
    let mut a1 = *a.at(1);
    let mut a2 = *a.at(2);
    let mut a3 = *a.at(3);
    let mut z0 = *z.at(0);
    let mut z1 = *z.at(1);
    let mut z2 = *z.at(2);
    let mut z3 = *z.at(3);
    let mut c = c;
    let mut t = t;
    let mut sums: Array<felt252> = array![];
    while let Some(cn) = c.pop_front() {
        sums
            .append(
                *a0.pop_front().unwrap() * *z0.pop_front().unwrap()
                    + *a1.pop_front().unwrap() * *z1.pop_front().unwrap()
                    + *a2.pop_front().unwrap() * *z2.pop_front().unwrap()
                    + *a3.pop_front().unwrap() * *z3.pop_front().unwrap()
                    + Q_SQUARED
                    - *cn * *t.pop_front().unwrap(),
            );
    }
    reduce(sums.span())
}
