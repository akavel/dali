{.experimental: "codeReordering".}
import strutils
import critbits
import bitops
import std/sha1
import sets
import hashes
import patty
import sortedset

# NOTE(akavel): this must be early, to make sure it's used, as codeReordering fails to move it
proc `<`(p1, p2: Prototype): bool =
  # echo "called <"
  if p1.ret != p2.ret:
    return p1.ret < p2.ret
  for i in 0 ..< min(p1.params.len, p2.params.len):
    if p1.params[i] != p2.params[i]:
      return p1.params[i] < p2.params[i]
  return p1.params.len < p2.params.len

converter toUint32[T: enum](s: set[T]): uint32 =
  for v in s:
    result = result or v.ord.uint32

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
    # Note: below fields are generally ordered from simplest to more complex
    # (in order of dependency)
    strings: CritBitTree[int]  # value: order of addition
    types: SortedSet[string]
    typeLists: seq[seq[Type]]
    # NOTE: prototypes must have no duplicates, TODO: and be sorted by:
    # (ret's type ID; args' type ID)
    prototypes: SortedSet[Prototype]
    # NOTE: fields must have no duplicates, TODO: and be sorted by:
    # (class type ID, field name's string ID, field's type ID)
    fields: SortedSet[tuple[class: Type, name: string, typ: Type]]
    # NOTE: methods must have no duplicates, TODO: and be sorted by:
    # (class type ID, name's string ID, prototype's proto ID)
    methods: SortedSet[tuple[class: Type, name: string, proto: Prototype]]
    classes*: seq[ClassDef]
  NotImplementedYetError* = object of CatchableError
  ConsistencyError* = object of CatchableError

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

proc hash*(proto: Prototype): Hash =
  var h: Hash = 0
  h = h !& hash(proto.ret)
  h = h !& hash(proto.params)
  result = !$h

proc newDex*(): Dex =
  new(result)
  init(result.prototypes)
  init(result.fields)
  init(result.methods)

proc render*(dex: Dex): string =
  dex.collect()
  var pos = 0
  # We skip the header, as most of it can only be calculated after the rest of the segments.
  pos += 0x60
  # We preallocate space for the list of string offsets. We cannot fill it yet, as its contents
  # will depend on the size of the other segments.
  pos += 4 * dex.strings.len
  #-- Render typeIDs.
  let stringIds = dex.stringsOrdering
  # dex.types are already stored sorted, same as dex.strings, so we don't need
  # to sort again by type IDs
  for t in dex.types:
    pos += result.write(pos, stringIds[dex.strings[t]].uint32)
  #-- Partially render proto IDs.
  # We cannot fill offsets for parameters (type lists), as they'll depend on the size of the
  # segments inbetween.
  for p in dex.prototypes:
    pos += result.write(pos, stringIds[dex.strings[p.descriptor]].uint32)
    pos += result.write(pos, dex.types.search(p.ret).uint32)
    pos += 4
    echo p.ret, " ", p.params
  #-- Render field IDs
  for f in dex.fields:
    pos += result.write_ushort(pos, dex.types.search(f.class).uint16)
    pos += result.write_ushort(pos, dex.types.search(f.typ).uint16)
    pos += result.write(pos, stringIds[dex.strings[f.name]].uint32)
  #-- Render method IDs
  for m in dex.methods:
    # echo $m
    pos += result.write_ushort(pos, dex.types.search(m.class).uint16)
    pos += result.write_ushort(pos, dex.prototypes.search(m.proto).uint16)
    pos += result.write(pos, stringIds[dex.strings[m.name]].uint32)
  #-- Partially render class defs.
  const NO_INDEX = 0xffff_ffff'u32
  for c in dex.classes:
    pos += result.write(pos, dex.types.search(c.class).uint32)
    pos += result.write(pos, c.access.uint32)
    match c.superclass:
      SomeType(t):
        pos += result.write(pos, dex.types.search(t).uint32)
      NoType:
        pos += result.write(pos, NO_INDEX)
    pos += result.write(pos, 0'u32)  # TODO: interfaces_off
    pos += result.write(pos, NO_INDEX)  # TODO: source_file_idx
    pos += result.write(pos, 0'u32)  # TODO: annotations_off
    pos += 4  # Here we'll need to fill class data offset
    pos += result.write(pos, 0'u32)  # TODO: static_values
  #-- Render code items
  for cd in dex.classes:
    for dm in cd.class_data.direct_methods:
      if dm.code.kind == MaybeCodeKind.SomeCode:
        let code = dm.code.code
        pos += result.write_ushort(pos, code.registers)
        pos += result.write_ushort(pos, code.ins)
        pos += result.write_ushort(pos, code.outs)
        pos += result.write_ushort(pos, 0'u16)   # TODO: tries_size
        pos += result.write(pos, 0'u32)  # TODO: debug_info_off
        pos += 4  # This shall be filled with size of instrs, in 16-bit code units
        pos += dex.renderInstrs(pos, result, code.instrs, stringIds)
        echo "TODO..."

proc collect(dex: Dex) =
  # Collect strings and all the things from classes.
  # (types, prototypes/signatures, fields, methods)
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
                dex.addField(f)
              StringXXXX(s):
                dex.addStr(s)
              MethodXXXX(m):
                dex.addMethod(m)

proc renderInstrs(dex: Dex, pos: int, buf: var string, instrs: openArray[Instr], stringIds: openArray[int]): int =
  var
    pos = pos
    high = true
  for instr in instrs:
    pos += buf.write(pos, instr.opcode.chr)
    for arg in instr.args:
      # FIXME(akavel): padding
      match arg:
        RawX(v):
          pos += buf.write_nibble(pos, v, high)
          high = not high
        RawXX(v):
          pos += buf.write(pos, $chr(v))
        RegX(v):
          pos += buf.write_nibble(pos, v, high)
          high = not high
        RegXX(v):
          pos += buf.write(pos, $chr(v))
        FieldXXXX(v):
          pos += buf.write_ushort(pos, dex.fields.search((v.class, v.name, v.typ)).uint16)
        StringXXXX(v):
          pos += buf.write_ushort(pos, stringIds[dex.strings[v]].uint16)
        MethodXXXX(v):
          pos += buf.write_ushort(pos, dex.methods.search((v.class, v.name, v.prototype)).uint16)

proc sget_object(reg: uint8, field: Field): Instr =
  return newInstr(0x62, RegXX(reg), FieldXXXX(field))
proc const_string(reg: uint8, s: String): Instr =
  return newInstr(0x1a, RegXX(reg), StringXXXX(s))
proc invoke_virtual(regC: uint4, regD: uint4, m: Method): Instr =
  return newInstr(0x6e, RawX(2), RawX(0), MethodXXXX(m), RegX(regD), RegX(regC), RawXX(0))
proc return_void(): Instr =
  return newInstr(0x0e, RawXX(0))

proc newInstr(opcode: uint8, args: varargs[Arg]): Instr =
  ## NOTE: We're assuming little endian encoding of the
  ## file here; 8-bit args should be ordered in
  ## "swapped order" vs. the one listed in official
  ## Android bytecode spec (i.e., add lower byte first,
  ## higher byte later). On the other hand, 16-bit
  ## words should not have contents rotated (just fill
  ## them as in the spec).
  return Instr(opcode: opcode, args: @args)

proc addField(dex: Dex, f: Field) =
  dex.addType(f.class)
  dex.addType(f.typ)
  dex.addStr(f.name)
  dex.fields.incl((f.class, f.name, f.typ))

proc addMethod(dex: Dex, m: Method) =
  dex.addType(m.class)
  dex.addPrototype(m.prototype)
  dex.addStr(m.name)
  dex.methods.incl((m.class, m.name, m.prototype))

proc addPrototype(dex: Dex, proto: Prototype) =
  dex.addType(proto.ret)
  dex.addTypeList(proto.params)
  dex.prototypes.incl(proto)
  dex.addStr(proto.descriptor)

proc descriptor(proto: Prototype): string =
  proc typeChar(t: Type): string =
    case t
    of "V", "Z", "B", "S", "C", "I", "J", "F", "D": return t
    else:
      if t.startsWith"[" or t.startsWith"L": return "L"
      else: raise newException(ConsistencyError, "unexpected type in prototype: " & t)
  result = typeChar(proto.ret)
  for p in proto.params:
    result &= typeChar(p)

proc addTypeList(dex: Dex, ts: seq[Type]) =
  for p in ts:
    dex.addType(p)
  if not dex.typeLists.contains(ts):
    dex.typeLists.add(ts)

proc addType(dex: Dex, t: Type) =
  dex.addStr(t)
  dex.types.incl(t)

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

proc renderStringsAndOffsets(dex: Dex, baseOffset: int): (string, string) =
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

# proc renderTypeLists(dex: Dex): string =
#   # FIXME(akavel): optimize proc stringsOrdering() to cache result
#   let stringIds = dex.stringsOrdering
#   var pos = 0
#   for ts in dex.typeLists:
#     pos += result.write(

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

proc write(s: var string, pos: int, what: char): int {.discardable.} =
  return s.write(pos, $what)

proc write(s: var string, pos: int, what: uint32): int {.discardable.} =
  # Little-endian
  var buf = newString(4)
  buf[0] = chr(what and 0xff)
  buf[1] = chr(what shr 8 and 0xff)
  buf[2] = chr(what shr 16 and 0xff)
  buf[3] = chr(what shr 24 and 0xff)
  s.write(pos, buf)
  return 4

proc write_ushort(s: var string, pos: int, what: uint16): int {.discardable.} =
  # Little-endian
  var buf = newString(2)
  buf[0] = chr(what and 0xff)
  buf[1] = chr(what shr 8 and 0xff)
  s.write(pos, buf)
  return 2

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

proc write_nibble(s: var string, pos: int, what: uint4, high: bool): int =
  if pos >= s.len:
    setLen(s, pos+1)
  if high:
    s[pos] = chr(what.uint8 shl 4)
    return 0
  else:
    s[pos] = chr(s[pos].ord.uint8 or what.uint8)
    return 1


proc adler32(s: string): uint32 =
  # https://en.wikipedia.org/wiki/Adler-32
  var a: uint32 = 1
  var b: uint32 = 0
  const MOD_ADLER = 65521
  for c in s:
    a = (a + c.uint32) mod MOD_ADLER
    b = (b + a) mod MOD_ADLER
  result = (b shl 16) or a
