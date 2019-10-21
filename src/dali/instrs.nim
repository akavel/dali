{.experimental: "codeReordering".}

import dali/types

proc move_result_object*(reg: uint8): Instr =
  return newInstr(0x0c, RegXX(reg))

proc return_void*(): Instr =
  return newInstr(0x0e, RawXX(0))
proc return_object*(reg: uint8): Instr =
  return newInstr(0x11, RawXX(reg))

proc const_high16*(reg: uint8, highBits: uint16): Instr =
  return newInstr(0x15, RegXX(reg), RawXXXX(highBits))
proc const_wide_16*(regs: uint8, v: int16): Instr =
  return newInstr(0x16, RegXX(regs), RawXXXX(v.uint16))
proc const_string*(reg: uint8, s: String): Instr =
  return newInstr(0x1a, RegXX(reg), StringXXXX(s))

proc new_instance*(reg: uint8, t: Type): Instr =
  return newInstr(0x22, RegXX(reg), TypeXXXX(t))

proc iget_wide*(regsA: uint4, regB: uint4, field: Field): Instr =
  return newInstr(0x53, RegX(regB), RegX(regsA), FieldXXXX(field))
proc iput_wide*(regsA: uint4, regB: uint4, field: Field): Instr =
  return newInstr(0x5a, RegX(regB), RegX(regsA), FieldXXXX(field))

proc sget_object*(reg: uint8, field: Field): Instr =
  return newInstr(0x62, RegXX(reg), FieldXXXX(field))

proc invoke_virtual*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x6e, regC, m)
proc invoke_virtual*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x6e, regC, regD, m)

proc invoke_super*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x6f, regC, m)
proc invoke_super*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x6f, regC, regD, m)

proc invoke_direct*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x70, regC, m)
proc invoke_direct*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x70, regC, regD, m)

proc invoke_static*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x71, regC, m)
proc invoke_static*(regC, regD: uint4, m: Method): Instr =
  return newInvoke2(0x71, regC, regD, m)


proc newInvoke1*(opcode: uint8, regC: uint4, m: Method): Instr =
  return newInstr(opcode, RawX(1), RawX(0), MethodXXXX(m), RawX(0), RegX(regC), RawXX(0))
proc newInvoke2*(opcode: uint8, regC: uint4, regD: uint4, m: Method): Instr =
  return newInstr(opcode, RawX(2), RawX(0), MethodXXXX(m), RawX(regD), RegX(regC), RawXX(0))

proc newInstr*(opcode: uint8, args: varargs[Arg]): Instr =
  ## NOTE: We're assuming little endian encoding of the
  ## file here; 8-bit args should be ordered in
  ## "swapped order" vs. the one listed in official
  ## Android bytecode spec (i.e., add lower byte first,
  ## higher byte later). On the other hand, 16-bit
  ## words should not have contents rotated (just fill
  ## them as in the spec).
  return Instr(opcode: opcode, args: @args)

