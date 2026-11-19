//! pq_hybrid: a hybrid ECDSA-STARK + Falcon-512 Starknet account.
//!
//! EXPERIMENTAL AND UNAUDITED. Built on OpenZeppelin cairo-pq-verifiers (MIT).
//! Testnet / demo use only; never hold real funds with these contracts.

pub mod consumer;
pub mod dormant;
pub mod guard;
pub mod hybrid;
pub mod migratable;
pub mod migratable_v2;
pub mod mldsa;
pub mod utils;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_browser;
#[cfg(test)]
mod tests_consumer;
#[cfg(test)]
mod tests_dormant;
#[cfg(test)]
mod tests_falcon1024_fixture;
#[cfg(test)]
mod tests_guard;
#[cfg(test)]
mod tests_pf;
#[cfg(test)]
mod tests_migration;
#[cfg(test)]
mod tests_mldsa_fixture;
#[cfg(test)]
mod tests_rotation_fixture;
#[cfg(test)]
mod tests_scheme;
#[cfg(test)]
mod tests_wallets;
#[cfg(test)]
mod tests_wallets_fixture;
