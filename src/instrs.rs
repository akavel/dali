use crate::types::{Arg::*, *};
use u4::u4;

macro_rules! instr {
    ($op:expr $(; $( $arg:expr ),* $(,)? )? ) => {
        Instr {
            opcode: $op,
            args: vec![ $( $( $arg, )* )? ],
        }
    }
}

pub fn return_void() -> Instr {
    instr!(0x0e; RawXX(0))
}

pub fn const_high16(reg: u8, high_bits: u16) -> Instr {
    instr!(0x15; RegXX(reg), RawXXXX(high_bits))
}
pub fn const_string(reg: u8, s: String) -> Instr {
    instr!(0x1a; RegXX(reg), StringXXXX(s))
}

pub fn sget_object(reg: u8, field: Field) -> Instr {
    instr!(0x62; RegXX(reg), FieldXXXX(field))
}

pub fn invoke_virtual2(reg_c: U4, reg_d: U4, m: Method) -> Instr {
    invoke2(0x6e, reg_c, reg_d, m)
}

pub fn invoke_super2(reg_c: U4, reg_d: U4, m: Method) -> Instr {
    invoke2(0x6f, reg_c, reg_d, m)
}

pub fn invoke_direct1(reg_c: U4, m: Method) -> Instr {
    instr!(0x70;
        RawX(u4!(1)), RawX(u4!(0)),
        MethodXXXX(m),
        RawX(u4!(0)), RegX(reg_c),
        RawXX(0),
    )
}

// helper
fn invoke2(opcode: u8, reg_c: U4, reg_d: U4, m: Method) -> Instr {
    instr!(opcode;
        RawX(u4!(2)), RawX(u4!(0)),
        MethodXXXX(m),
        RegX(reg_d), RegX(reg_c),
        RawXX(0),
    )
}
