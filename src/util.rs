use std::borrow::Borrow;
use std::collections::BTreeMap;
use std::io::Write;
use std::rc::Rc;

use num::ToPrimitive;
use u4::{u4, U4x2, U4};

pub trait VecU8Ext {
    fn pos(&self) -> u32;
    fn pad32(&mut self);
    fn put_u4(&mut self, v: U4, high: &mut bool);
    fn put_u8(&mut self, v: u8);
    fn put_u16(&mut self, v: u16);
    fn put_u3216(&mut self, v: u32);
    fn put_usz16(&mut self, v: usize);
    fn put_u32(&mut self, v: u32);
    fn put_usz32(&mut self, v: usize);
    fn put_uleb128(&mut self, v: u32);
    fn slot32(&mut self) -> Slot32;
    fn set(&mut self, slot: Slot32, v: u32);
}

impl VecU8Ext for Vec<u8> {
    fn pos(&self) -> u32 {
        self.len().to_u32().unwrap()
    }

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

    fn put_u8(&mut self, v: u8) {
        self.push(v);
    }

    fn put_u16(&mut self, v: u16) {
        self.write(&v.to_le_bytes());
    }

    fn put_u3216(&mut self, v: u32) {
        self.put_u16(v.try_into().unwrap());
    }

    fn put_usz16(&mut self, v: usize) {
        self.put_u16(v.try_into().unwrap());
    }

    fn put_u32(&mut self, v: u32) {
        self.write(&v.to_le_bytes());
    }

    fn put_usz32(&mut self, v: usize) {
        self.put_u32(v.try_into().unwrap());
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

    fn slot32(&mut self) -> Slot32 {
        let slot = Slot32 {
            offset: Some(self.len()),
        };
        self.write(&[0u8; 4]);
        slot
    }

    fn set(&mut self, mut slot: Slot32, v: u32) {
        let i = slot.offset.take().unwrap();
        let b = v.to_le_bytes();
        self[i + 0] = b[0];
        self[i + 1] = b[1];
        self[i + 2] = b[2];
        self[i + 3] = b[3];
    }
}

pub struct Slot32 {
    offset: Option<usize>,
}

#[derive(Default)]
pub struct Slots32<T> {
    map: BTreeMap<T, Vec<Rc<Slot32>>>,
}

impl<T> Slots32<T> {
    pub fn new() -> Self {
        Self {
            map: BTreeMap::new(),
        }
    }

    pub fn contains<Q>(&self, key: &Q) -> bool
    where
        T: Borrow<Q> + Ord,
        Q: Ord + ?Sized,
    {
        self.map.contains_key(key)
    }

    pub fn len(&self) -> usize {
        self.map.len()
    }

    pub fn set_all_here<Q>(&mut self, key: &Q, blob: &mut Vec<u8>)
    where
        T: Borrow<Q> + Ord,
        Q: Ord + ?Sized,
    {
        let pos = blob.len().to_u32().unwrap();
        self.set_all(key, pos, blob);
    }

    fn set_all<Q>(&mut self, key: &Q, v: u32, blob: &mut Vec<u8>)
    where
        T: Borrow<Q> + Ord,
        Q: Ord + ?Sized,
    {
        let Some(slots) = self.map.remove(key) else {
            return;
        };
        for slot in slots {
            blob.set(Rc::into_inner(slot).unwrap(), v);
        }
    }
}

impl<T: Ord> Slots32<T> {
    pub fn insert(&mut self, key: T, value: Slot32) {
        self.map
            .entry(key)
            .or_insert_with(|| vec![])
            .push(Rc::new(value));
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
