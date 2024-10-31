use std::io::Write;
use u4::{u4, U4x2, U4};

pub trait VecU8Ext {
    fn pad32(&mut self);
    fn put_u4(&mut self, v: U4, high: &mut bool);
    fn put_uleb128(&mut self, v: u32);
}

impl VecU8Ext for Vec<u8> {
    fn pad32(&mut self) {
        let n = (4 - (self.len() % 4)) % 4;
        self.write(&vec![0u8; n]);
    }

    fn put_u4(&mut self, v: U4, high: &mut bool) {
        if *high {
            self.push(U4x2::new(v, u4!(0)).packed);
        } else {
            let i = self.len() - 1;
            self[i] = U4x2::from_byte(self[i]).with_right(v).packed;
        }
        *high = !*high;
    }

    /// Writes an uint32 in ULEB128 format
    /// (https://source.android.com/devices/tech/dalvik/dex-format#leb128)
    fn put_uleb128(&mut self, v: u32) {
        if v == 0 {
            self.write(&[0u8]);
            return;
        }
        let top_bit = v.ilog2(); // position of the highest bit set
        let n = top_bit / 7 + 1; // number of bytes required for ULEB128 encoding of 'v'
        let mut buf = vec![0; n.try_into().unwrap()];
        let mut work = v;
        let mut i = 0;
        while work >= 0x80u32 {
            buf[i] = 0x80u8 | (work & 0x7f) as u8;
            work >>= 7;
            i += 1;
        }
        buf[i] = work as u8;
        self.write(&buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use pretty_hex::*;

    type Blob = Vec<u8>;

    #[test]
    fn test_pad32() {
        fn pad(s: &str) -> Blob {
            let mut b = Blob::new();
            b.write(s.as_bytes());
            b.pad32();
            b
        }
        assert_eq!(pretty_hex(&pad("")), pretty_hex(&""));
        assert_eq!(pretty_hex(&pad("a")), pretty_hex(&"a\x00\x00\x00"));
        assert_eq!(pretty_hex(&pad("ab")), pretty_hex(&"ab\x00\x00"));
        assert_eq!(pretty_hex(&pad("abc")), pretty_hex(&"abc\x00"));
        assert_eq!(pretty_hex(&pad("abcd")), pretty_hex(&"abcd"));
        assert_eq!(pretty_hex(&pad("abcde")), pretty_hex(&"abcde\x00\x00\x00"));
    }

    #[test]
    fn test_put_uleb128() {
        fn uleb(n: u32) -> Blob {
            let mut b = Blob::new();
            b.put_uleb128(n);
            b
        }
        assert_eq!(uleb(0), [0x00u8]);
        assert_eq!(uleb(1), [0x01u8]);
        assert_eq!(uleb(127), [0x7Fu8]);
        assert_eq!(uleb(16256), [0x80u8, 0x7Fu8]);
    }

    #[test]
    fn test_put4() {
        let mut b = Blob::new();
        let mut high = true;
        b.put_u4(u4!(0xf), &mut high);
        b.put_u4(u4!(0xa), &mut high);
        b.put_u4(u4!(0x1), &mut high);
        b.put_u4(u4!(0x2), &mut high);
        assert_eq!(b, [0xFAu8, 0x12u8]);
    }
}
