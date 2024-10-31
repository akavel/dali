use std::io::Write;
use u4::{u4, U4x2, U4};

pub trait VecU8Ext {
    fn pad32(&mut self);
    fn put_u4(&mut self, v: U4, high: &mut bool);
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
}
