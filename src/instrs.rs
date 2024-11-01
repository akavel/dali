use crate::types::{Arg::*, *};
use u4::u4;

pub fn return_void() -> Instr {
    Instr {
        opcode: 0x0e,
        args: vec![RawXX(0)],
    }
}

pub fn const_high16(reg: u8, high_bits: u16) -> Instr {
    Instr {
        opcode: 0x15,
        args: vec![RegXX(reg), RawXXXX(high_bits)],
    }
}
pub fn const_string(reg: u8, s: String) -> Instr {
    Instr {
        opcode: 0x1a,
        args: vec![RegXX(reg), StringXXXX(s)],
    }
}

pub fn sget_object(reg: u8, field: Field) -> Instr {
    Instr {
        opcode: 0x62,
        args: vec![RegXX(reg), FieldXXXX(field)],
    }
}

pub fn invoke_virtual2(reg_c: U4, reg_d: U4, m: Method) -> Instr {
    invoke2(0x6e, reg_c, reg_d, m)
}

pub fn invoke_super2(reg_c: U4, reg_d: U4, m: Method) -> Instr {
    invoke2(0x6f, reg_c, reg_d, m)
}

pub fn invoke_direct1(reg_c: U4, m: Method) -> Instr {
    Instr {
        opcode: 0x70,
        args: vec![
            RawX(u4!(1)),
            RawX(u4!(0)),
            MethodXXXX(m),
            RawX(u4!(0)),
            RegX(reg_c),
            RawXX(0),
        ],
    }
}

// helper
fn invoke2(opcode: u8, reg_c: U4, reg_d: U4, m: Method) -> Instr {
    Instr {
        opcode,
        args: vec![
            RawX(u4!(2)),
            RawX(u4!(0)),
            MethodXXXX(m),
            RegX(reg_d),
            RegX(reg_c),
            RawXX(0),
        ],
    }
}
