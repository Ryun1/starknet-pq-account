//! PF-13 benchmarks, measured as bench/pf04 does: every measurement is a pair of tests, `setup_*`
//! builds the state and inputs, the measured test builds the same and makes one call, and the
//! call's cost is the difference of the two reported L2 gas figures.

#[cfg(test)]
mod bench;
#[cfg(test)]
mod cases;
pub mod legacy;
