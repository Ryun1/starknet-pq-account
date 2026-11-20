pub mod ct;
pub mod encx;
pub use encx as encoding;
mod nttu;
pub mod k2;
pub mod kc0;
pub use kc0 as keccak;
pub mod nt0;
pub use nt0 as ntt;
pub mod pk0;
pub use pk0 as packing;
pub mod sa0;
pub use sa0 as sampling;
pub mod verx;
pub use verx as verify;
pub mod x2;
pub mod zread;
use pqbench_interface::PqSignatureVerifier;
pub const PK_FELTS:u32=43;
pub const SIG_FELTS:u32=79;
pub impl MlDsa44Verifier of PqSignatureVerifier{
fn verify(message_hash:felt252,public_key:Span<felt252>,signature:Span<felt252>)->bool{
verx::tac(public_key,signature,message_hash)
}
}

#[derive(Copy,Drop)]
pub struct W{pub v:ct::Rh}
#[derive(Copy,Drop)]
pub struct Z{pub v:nttu::Zb}
#[derive(Drop)]
pub struct H{pub p0:nttu::Zc,pub p1:nttu::Zc,pub p2:nttu::Zc,pub p3:nttu::Zc,pub p4:nttu::Zc,pub p5:nttu::Zc,pub p6:nttu::Zc,pub p7:nttu::Zc,pub p8:nttu::Zc,pub p9:nttu::Zc,pub p10:nttu::Zc,pub p11:nttu::Zc,pub p12:nttu::Zc,pub p13:nttu::Zc,pub p14:nttu::Zc,pub p15:nttu::Zc}
#[derive(Drop)]
pub struct V{pub p0:H,pub p1:H,pub p2:H,pub p3:H,pub p4:H,pub p5:H,pub p6:H,pub p7:H}
