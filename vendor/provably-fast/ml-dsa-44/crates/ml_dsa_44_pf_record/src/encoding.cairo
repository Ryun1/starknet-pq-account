//! The challenge's felt encoding: keys and signatures as felts of 31 little-endian bytes, and the
//! message hash as the felt's 32 big-endian bytes.

const FELT_BYTES: u32 = 31;

/// `felts` as `total` bytes, 31 to a felt, little-endian within each felt and the last felt holding
/// the rest. None when the count is wrong or a felt has a bit set above its bytes, so every byte
/// string has exactly one encoding.
pub fn felts_to_bytes(felts: Span<felt252>, total: u32) -> Option<Array<u8>> {
    if felts.len() != (total + FELT_BYTES - 1) / FELT_BYTES {
        return None;
    }
    let mut out: Array<u8> = array![];
    let mut remaining = total;
    let mut canonical = true;
    for felt in felts {
        let size = if remaining < FELT_BYTES {
            remaining
        } else {
            FELT_BYTES
        };
        let value: u256 = (*felt).into();
        let low_size = if size < 16 {
            size
        } else {
            16
        };
        // Each half must be used up by its bytes: anything left is a bit above them.
        if take_le(value.low, low_size, ref out) != 0
            || take_le(value.high, size - low_size, ref out) != 0 {
            canonical = false;
            break;
        }
        remaining -= size;
    }
    if canonical {
        Some(out)
    } else {
        None
    }
}

/// Append the low `count` bytes of `x`, least significant first, and return what is above them.
fn take_le(x: u128, count: u32, ref out: Array<u8>) -> u128 {
    let byte: NonZero<u128> = 256_u128.try_into().unwrap();
    let mut rest = x;
    let mut k = 0;
    while k != count {
        let (above, low) = DivRem::div_rem(rest, byte);
        out.append(low.try_into().unwrap());
        rest = above;
        k += 1;
    }
    rest
}

/// M' for a message hash under the empty context (FIPS 204, Algorithm 3):
/// 0x00 || 0x00 || the felt as 32 big-endian bytes.
pub fn message_prime(message_hash: felt252) -> Array<u8> {
    let value: u256 = message_hash.into();
    let mut le: Array<u8> = array![];
    take_le(value.low, 16, ref le);
    take_le(value.high, 16, ref le);
    let mut out: Array<u8> = array![0, 0];
    let mut bytes = le.span();
    while let Some(byte) = bytes.pop_back() {
        out.append(*byte);
    }
    out
}
