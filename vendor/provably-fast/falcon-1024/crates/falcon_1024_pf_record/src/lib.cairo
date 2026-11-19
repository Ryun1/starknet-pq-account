//! Falcon-1024 (FN-DSA at NIST's level 5) signature verification for Starknet.
//!
//! `Falcon1024Verifier::verify` checks a Falcon-1024 signature over the transaction hash in the
//! Falcon-512 season's hint layout, at n = 1024:
//!
//! - the public key is the NTT-domain key h packed base q, 57 felts;
//! - the signature is packed s1 (57 felts) || the 40-byte salt as two 20-byte little-endian felts
//!   || packed mul_hint = s1 * h (57 felts);
//! - the message point is the standard SHAKE-256 hash-to-point of salt || the felt's 32
//!   little-endian bytes.
//!
//! A signature is valid when NTT(s1) * h_ntt == NTT(mul_hint) pointwise mod q, which binds the
//! hint to s1 * h, and ||message point - mul_hint||^2 + ||s1||^2 <= 70,265,242 over centered
//! coefficients. Checked against falcon.py (tests/).

pub mod falcon;
mod fk;
pub mod fixtures;
pub mod hash_to_point;
pub mod keccak;
pub mod ntt;
pub mod packing;
use pqbench_interface::PqSignatureVerifier;

pub const PUBKEY_FELTS: u32 = 57;
pub const SIG_FELTS: u32 = 116;

pub impl Falcon1024Verifier of PqSignatureVerifier {
    #[inline(never)]
fn verify(message_hash: felt252, public_key: Span<felt252>, signature: Span<felt252>) -> bool {
        if public_key.len() != PUBKEY_FELTS {
            return false;
        }
let sbx: Option<@Box<[felt252; 116]>> = signature.try_into();
let Some(sbx) = sbx else { return false; };
let [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,sa,sb,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_]=(*sbx).unbox();
let point=
match hash_to_point::hash_to_point(message_hash, sa, sb) {
            Some(v) => v,
            None => { return false; },
        };
let s1p=signature;let ps=point.span();let (nq,mk,hm)=packing::cells();
let (a,b,c,d,e,f,g)=packing::uw7(s1p,ps,nq,mk,hm);
if d==0 {
return vslow(s1p,ps,(a,b,c,d,e,f,g),public_key);
}
let st=(a,b,c,d,e,f,g);
let(ev,eo,pnorm) =match packing::ubt(st) {
            packing::UbtR::Ok(v) => v,
            packing::UbtR::Slow(t) => { return vtail(s1p, ps, t, public_key); },
            packing::UbtR::Fail => { return false; },
        };

if let Err(n)=core::internal::bounded_int::constrain::<_,70265243,packing::SnBound>(pnorm) {
return falcon::rare(pqbench_ntt_f1024_pf_record::ci::bounded_int::upcast(n),ev,eo,public_key,nq,signature,ps);
}
falcon::verify_with_hint(ev,eo.span(),public_key,nq)
    }
}



/// verify's continuation for a signature whose fast decoder stopped at a block (narrow or
/// non-canonical felt): slow7, then the same norm and hint checks as verify.
#[inline(never)]
fn vslow(
    s1p: Span<felt252>, ps: Span<hash_to_point::Acc5>, t: packing::St, public_key: Span<felt252>,
) -> bool {
    let st = match packing::slow7(s1p, ps, t) {
        Some(t) => t,
        None => { return false; },
    };
    vtail(s1p, ps, st, public_key)
}

/// The last block (ubtc: narrow last felts accepted), the norm and the hint checks: vslow's tail, and verify's
/// route for a narrow last felt (the hot ubt splits it Wide-only).
#[inline(never)]
fn vtail(
    s1p: Span<felt252>, ps: Span<hash_to_point::Acc5>, st: packing::St, public_key: Span<felt252>,
) -> bool {
    let (nq, _, _) = packing::cells();
    let (ev, eo, pnorm) = match ubtw(st) {
        Some(v) => v,
        None => { return false; },
    };
    if let Err(n) = core::internal::bounded_int::constrain::<_, 70265243, packing::SnBound>(pnorm) {
        return falcon::rare(pqbench_ntt_f1024_pf_record::ci::bounded_int::upcast(n), ev, eo, public_key, nq, s1p, ps);
    }
    falcon::vwh(ev, eo, public_key, nq)
}

/// ubt out of line for vslow (keeps vslow's frame small).
#[inline(never)]
fn ubtw(t: packing::St) -> Option<(Span<pqbench_ntt_f1024_pf_record::J>, Array<pqbench_ntt_f1024_pf_record::J>, packing::SN)> {
    packing::ubtc(t)
}
