//! ML-DSA-44 verification over bytes (FIPS 204, Algorithm 8).

use crate::keccak::shake256;
use crate::ntt::{intt, ntt, row};
use crate::packing::{hint_valid, t1_scaled, use_hints, w1_encode, z_unpack};
use crate::sampling::{expand_a, sample_in_ball};

pub const PK_BYTES: u32 = 1312;
pub const SIG_BYTES: u32 = 2420;
const C_TILDE_BYTES: u32 = 32;
const T1_BYTES: u32 = 320;
const Z_BYTES: u32 = 576;
const HINT_AT: u32 = 2336; // 32 + 4 * 576
const OMEGA: u32 = 80;

/// ML-DSA.Verify_internal (Algorithm 8) on M'.
pub fn verify_internal(pk: Span<u8>, message_prime: Span<u8>, sig: Span<u8>) -> bool {
    if pk.len() != PK_BYTES {
        return false;
    }
    let tr = shake256(pk, 64);
    let mut input: Array<u8> = array![];
    input.append_span(tr.span());
    input.append_span(message_prime);
    let mu = shake256(input.span(), 64);
    verify_mu(pk, mu.span(), sig)
}

/// Algorithm 8 from mu = H(tr || M', 64) on, FIPS 204's external-mu form. The checks that need no
/// hashing (lengths, the hint, ||z||inf) come first.
pub fn verify_mu(pk: Span<u8>, mu: Span<u8>, sig: Span<u8>) -> bool {
    if pk.len() != PK_BYTES || sig.len() != SIG_BYTES || mu.len() != 64 {
        return false;
    }
    let hint = sig.slice(HINT_AT, OMEGA + 4);
    if !hint_valid(hint) {
        return false;
    }
    let mut z_hat: Array<Span<felt252>> = array![];
    let mut j = 0;
    while j != 4 {
        match z_unpack(sig.slice(C_TILDE_BYTES + Z_BYTES * j, Z_BYTES)) {
            Some(z) => z_hat.append(ntt(z.span()).span()),
            None => { break; },
        }
        j += 1;
    }
    if z_hat.len() != 4 {
        return false;
    }
    let z_hat = z_hat.span();
    let a_hat = expand_a(pk.slice(0, 32));
    let c_tilde = sig.slice(0, C_TILDE_BYTES);
    let c_hat = ntt(sample_in_ball(c_tilde).span());
    let mut h_input: Array<u8> = array![];
    h_input.append_span(mu);
    let mut first: u32 = 0;
    let mut i = 0;
    while i != 4 {
        let t1_hat = ntt(t1_scaled(pk.slice(32 + T1_BYTES * i, T1_BYTES)).span());
        let w_approx = intt(
            row(a_hat.span().slice(4 * i, 4), z_hat, c_hat.span(), t1_hat.span()).span(),
        );
        let end: u32 = (*hint.at(OMEGA + i)).into();
        let w1 = use_hints(w_approx.span(), hint.slice(first, end - first));
        w1_encode(w1.span(), ref h_input);
        first = end;
        i += 1;
    }
    shake256(h_input.span(), C_TILDE_BYTES).span() == c_tilde
}
