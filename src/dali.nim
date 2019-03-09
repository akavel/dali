{.experimental: "codeReordering".}
import strutils
import critbits
import bitops
import std/sha1
import patty

# Potentially useful bibliography
#
# DEX:
# - https://github.com/corkami/pics/blob/master/binary/DalvikEXecutable.pdf
# - [dex-format]: https://source.android.com/devices/tech/dalvik/dex-format
# - https://blog.bugsnag.com/dex-and-d8/
# - http://benlynn.blogspot.com/2009/02/minimal-dalvik-executables_06.html
#
# APK:
# - https://fractalwrench.co.uk/posts/playing-apk-golf-how-low-can-an-android-app-go/
# - https://github.com/fractalwrench/ApkGolf
#
# Opcodes:
# - https://github.com/corkami/pics/blob/master/binary/opcodes_tables_compact.pdf
# - https://source.android.com/devices/tech/dalvik/dalvik-bytecode.html
#
# MORE:
# - https://github.com/JesusFreke/smali
# - https://github.com/linkedin/dexmaker
# - https://github.com/iBotPeaches/Apktool

variant Arg:  # Argument of an instruction of Dalvik bytecode
  RawX(raw4: uint4)
  RawXX(raw8: uint8)
  RegX(reg4: uint4)
  RegXX(reg8: uint8)
  FieldXXXX(field16: Field)
  StringXXXX(string16: String)
  MethodXXXX(method16: Method)

variantp MaybeType:
  SomeType(typ: Type)
  NoType

variantp MaybeCode:
  SomeCode(code: Code)
  NoCode


type
  Dex* = ref object
    strings: CritBitTree[int]  # value: order of addition
    types: CritBitTree[int]    # value: order of addition
    classes*: seq[ClassDef]
  NotImplementedYetError* = object of CatchableError

  Field* = ref object
    class*: Type
    typ*: Type
    name*: String
  Type* = String
  String* = string
  Method* = ref object
    class*: Type
    prototype*: Prototype  # a.k.a. method signature
    name*: String
  Prototype* = ref object
    descriptor*: String
    ret*: Type
    params*: TypeList
  TypeList* = seq[Type]

  uint4* = range[0..15]   # e.g. register v0..v15

type
  Instr* = ref object
    opcode: uint8
    args: seq[Arg]
  Code* = ref object
    registers*: uint16
    ins*: uint16
    outs*: uint16
    # tries: ?
    # debug_info: ?
    instrs*: seq[Instr]

type
  ClassDef* = ref object
    class*: Type
    access*: set[Access]
    superclass*: MaybeType
    # interfaces: TypeList
    # sourcefile: String
    # annotations: ?
    class_data*: ClassData
    # static_values: ?
  ClassData* = ref object
    # static_fields*: ?
    # instance_fields*: ?
    direct_methods*: seq[EncodedMethod]
    # virtual_methods*: ?
  EncodedMethod* = ref object
    m*: Method
    access*: set[Access]
    code*: MaybeCode
  Access* = enum
    Public = 0x1
    Private = 0x2
    Protected = 0x4
    Static = 0x8
    Final = 0x10
    Synchronized = 0x20
    Varargs = 0x80
    Interface = 0x200
    Abstract = 0x400
    Annotation = 0x2000
    Enum = 0x4000
    Constructor = 0x1_0000

proc newDex*(): Dex =
  new(result)

proc dump*(dex: Dex): string =
  for cd in dex.classes:
    dex.addType(cd.class)
    if cd.superclass.kind == MaybeTypeKind.SomeType:
      dex.addType(cd.superclass.typ)
    for dm in cd.class_data.direct_methods:
      dex.addMethod(dm.m)
      if dm.code.kind == MaybeCodeKind.SomeCode:
        for instr in dm.code.code.instrs:
          for arg in instr.args:
            match arg:
              RawX(r): discard
              RawXX(r): discard
              RegX(r): discard
              RegXX(r): discard
              FieldXXXX(f):
                dex.addType(f.class)
                dex.addType(f.typ)
                dex.addStr(f.name)
              StringXXXX(s):
                dex.addStr(s)
              MethodXXXX(m):
                dex.addMethod(m)
  let (s, off) = dex.dumpStringsAndOffsets(228)
  return ' '.repeat(10) & s

proc sget_object(reg: uint8, field: Field): Instr =
  return newInstr(0x62, RegXX(reg), FieldXXXX(field))
proc const_string(reg: uint8, s: String): Instr =
  return newInstr(0x1a, RegXX(reg), StringXXXX(s))
proc invoke_virtual(m: Method, regC: uint4, regD: uint4): Instr =
  return newInstr(0x6e, RawX(2), RawX(0), MethodXXXX(m), RegX(regD), RegX(regC), RawXX(0))
proc return_void(): Instr =
  return newInstr(0x0e, RawXX(0))

proc newInstr(opcode: uint8, args: varargs[Arg]): Instr =
  return Instr(opcode: opcode, args: @args)


proc addMethod(dex: Dex, m: Method) =
  dex.addType(m.class)
  dex.addType(m.prototype.ret)
  for p in m.prototype.params:
    dex.addType(p)
  dex.addStr(m.prototype.descriptor)
  dex.addStr(m.name)

proc addType(dex: Dex, t: Type) =
  dex.addStr(t)
  discard dex.types.containsOrIncl(t, dex.types.len)

proc addStr(dex: Dex, s: string) =
  if s.contains({'\x00', '\x80'..'\xFF'}):
    raise newException(NotImplementedYetError, "strings with 0x00 or 0x80..0xFF bytes are not yet supported")
  discard dex.strings.containsOrIncl(s, dex.strings.len)
  # "This list must be sorted by string contents, using UTF-16 code point
  # values (not in a locale-sensitive manner), and it must not contain any
  # duplicate entries." [dex-format] <- I think this is guaranteed by UTF-8 + CritBitTree type

proc stringsOrdering(dex: Dex): seq[int] =
  var i = 0
  newSeq(result, dex.strings.len)
  for s, added in dex.strings:
    result[added] = i
    inc i

proc stringsAsAdded(dex: Dex): seq[string] =
  newSeq(result, dex.strings.len)
  for s, added in dex.strings:
    result[added] = s

proc dumpStringsAndOffsets(dex: Dex, baseOffset: int): (string, string) =
  var
    ordering = dex.stringsOrdering
    offsets = newString(4 * dex.strings.len)
    buf = ""
    pos = 0
  for s in dex.stringsAsAdded:
    offsets.write(4 * ordering[dex.strings[s]], uint32(baseOffset + pos))
    # FIXME: MUTF-8: encode U+0000 as hex: C0 80
    # FIXME: MUTF-8: use CESU-8 to encode code-points from beneath Basic Multilingual Plane (> U+FFFF)
    # FIXME: length *in UTF-16 code units*, as ULEB128
    pos += buf.write_uleb128(pos, s.len.uint32)
    pos += buf.write(pos, s & "\x00")
  return (buf, offsets)

proc sample_dex(tail: string): string =
  var header = newString(0x2C)
  # Magic prefix
  # TODO: handle various versions of targetSdkVersion file, not only 035
  header.write(0, "dex\n035\x00")
  # File size
  header.write(0x20, header.len.uint32 + tail.len.uint32)
  # Header size
  header.write(0x24, 0x70'u32)
  # Endian constant
  header.write(0x28, 0x12345678)

  # SHA1 hash
  # TODO: should allow hashing a "stream", to not allocate new string...
  let sha1 = secureHash(header.substr(0x20) & tail)
  header.write(0x0c, parseHexStr($sha1))  # FIXME(akavel): should not have to go through string!
  # Adler checksum
  header.write(0x08, adler32(header.substr(0x0c) & tail))
  return header & tail

proc write(s: var string, pos: int, what: string): int {.discardable.} =
  if pos + what.len > s.len:
    setLen(s, pos + what.len)
  copyMem(addr(s[pos]), cstring(what), what.len)
  return what.len

proc write(s: var string, pos: int, what: uint32): int {.discardable.} =
  # Little-endian
  var buf = newString(4)
  buf[0] = chr(what and 0xff)
  buf[1] = chr(what shr 8 and 0xff)
  buf[2] = chr(what shr 16 and 0xff)
  buf[3] = chr(what shr 24 and 0xff)
  s.write(pos, buf)
  return 4

proc write_uleb128(s: var string, pos: int, what: uint32): int =
  ## Writes an uint32 in ULEB128 (https://source.android.com/devices/tech/dalvik/dex-format#leb128)
  ## format, returning the number of bytes taken by the encoding.
  if what == 0:
    s.write(pos, "\x00")
    return 1
  let
    topBit = fastLog2(what)  # position of the highest bit set
    n = topBit div 7 + 1         # number of bytes required for ULEB128 encoding of 'what'
  var
    buf = newString(n.Natural)
    work = what
    i = 0
  while work >= 0x80'u32:
    buf[i] = chr(0x80.byte or (work and 0x7F).byte)
    work = work shr 7
    inc i
  buf[i] = chr(work.byte)
  s.write(pos, buf)
  return n



proc adler32(s: string): uint32 =
  # https://en.wikipedia.org/wiki/Adler-32
  var a: uint32 = 1
  var b: uint32 = 0
  const MOD_ADLER = 65521
  for c in s:
    a = (a + c.uint32) mod MOD_ADLER
    b = (b + a) mod MOD_ADLER
  result = (b shl 16) or a

