{.experimental: "codeReordering".}
import strutils
import critbits
import bitops
import std/sha1
import sets
import tables
import hashes
import patty
import dali/sortedset
import dali/blob

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
  RawXXXX(raw16: uint16)
  RegX(reg4: uint4)
  RegXX(reg8: uint8)
  FieldXXXX(field16: Field)
  StringXXXX(string16: String)
  TypeXXXX(type16: Type)
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
    outs*: uint16 # "the number of words of outgoing argument space required by this code for method invocation"
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
    virtual_methods*: seq[EncodedMethod]
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
    Native = 0x100
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

  # Storage for offsets where various sections of the file
  # start. Will be needed to render map_list.
  var sectionOffsets = newSeq[tuple[typ: uint16, size: uint32, offset: uint32]]()

  # FIXME: ensure correct padding everywhere
  var blob = "".Blob
  #-- Partially render header
  # Most of it can only be calculated after the rest of the segments.
  sectionOffsets.add((0x0000'u16, 1'u32, blob.pos))
  # TODO: handle various versions of targetSdkVersion file, not only 035
  blob.puts("dex\n035\x00")  # Magic prefix
  let adlerSumSlot = blob.slot32()
  blob.reserve(20)        # TODO: Fill sha1 sum
  let fileSizeSlot = blob.slot32()
  blob.put32(0x70)        # Header size
  blob.put32(0x12345678)  # Endian constant
  blob.put32(0)           # link_size
  blob.put32(0)           # link_off
  let mapOffsetSlot = blob.slot32()
  blob.put32(dex.strings.len.uint32)
  let stringIdsOffSlot = blob.slot32()
  blob.put32(dex.types.len.uint32)
  let typeIdsOffSlot = blob.slot32()
  blob.put32(dex.prototypes.len.uint32)
  let protoIdsOffSlot = blob.slot32()
  blob.put32(dex.fields.len.uint32)
  let fieldIdsOffSlot = blob.slot32()
  blob.put32(dex.methods.len.uint32)
  let methodIdsOffSlot = blob.slot32()
  blob.put32(dex.classes.len.uint32)
  let classDefsOffSlot = blob.slot32()
  let dataSizeSlot = blob.slot32()
  let dataOffSlot = blob.slot32()
  # blob.reserve(0x70 - blob.pos.int)
  #-- Partially render string_ids
  # We preallocate space for the list of string offsets. We cannot fill it yet, as its contents
  # will depend on the size of the other segments.
  sectionOffsets.add((0x0001'u16, dex.strings.len.uint32, blob.pos))
  blob.set(stringIdsOffSlot, blob.pos)
  var stringOffsets = newSeq[Slot32](dex.strings.len)
  for i in 0 ..< dex.strings.len:
    stringOffsets[i] = blob.slot32()
  #-- Render typeIDs.
  sectionOffsets.add((0x0002'u16, dex.types.len.uint32, blob.pos))
  blob.set(typeIdsOffSlot, blob.pos)
  let stringIds = dex.stringsOrdering
  # dex.types are already stored sorted, same as dex.strings, so we don't need
  # to sort again by type IDs
  for t in dex.types:
    blob.put32(stringIds[dex.strings[t]].uint32)
  #-- Partially render proto IDs.
  # We cannot fill offsets for parameters (type lists), as they'll depend on the size of the
  # segments inbetween.
  sectionOffsets.add((0x0003'u16, dex.prototypes.len.uint32, blob.pos))
  blob.set(protoIdsOffSlot, blob.pos)
  var typeListOffsets = newSlots32[seq[Type]]()
  for p in dex.prototypes:
    blob.put32(stringIds[dex.strings[p.descriptor]].uint32)
    blob.put32(dex.types.search(p.ret).uint32)
    typeListOffsets.add(p.params, blob.slot32())
    # echo p.ret, " ", p.params
  #-- Render field IDs
  if dex.fields.len > 0:
    sectionOffsets.add((0x0004'u16, dex.fields.len.uint32, blob.pos))
    blob.set(fieldIdsOffSlot, blob.pos)
  for f in dex.fields:
    blob.put16(dex.types.search(f.class).uint16)
    blob.put16(dex.types.search(f.typ).uint16)
    blob.put32(stringIds[dex.strings[f.name]].uint32)
  #-- Render method IDs
  sectionOffsets.add((0x0005'u16, dex.methods.len.uint32, blob.pos))
  if dex.methods.len > 0:
    blob.set(methodIdsOffSlot, blob.pos)
  for m in dex.methods:
    # echo $m
    blob.put16(dex.types.search(m.class).uint16)
    blob.put16(dex.prototypes.search(m.proto).uint16)
    blob.put32(stringIds[dex.strings[m.name]].uint32)
  #-- Partially render class defs.
  sectionOffsets.add((0x0006'u16, dex.classes.len.uint32, blob.pos))
  blob.set(classDefsOffSlot, blob.pos)
  var classDataOffsets = newSlots32[Type]()
  const NO_INDEX = 0xffff_ffff'u32
  for c in dex.classes:
    blob.put32(dex.types.search(c.class).uint32)
    blob.put32(c.access.uint32)
    match c.superclass:
      SomeType(t):
        blob.put32(dex.types.search(t).uint32)
      NoType:
        blob.put32(NO_INDEX)
    blob.put32(0'u32)  # TODO: interfaces_off
    blob.put32(NO_INDEX)  # TODO: source_file_idx
    blob.put32(0'u32)  # TODO: annotations_off
    classDataOffsets.add(c.class, blob.slot32())
    blob.put32(0'u32)  # TODO: static_values
  #-- Render code items
  let codeOffset = blob.pos
  var codeItems = 0'u32
  blob.set(dataOffSlot, blob.pos)
  let dataStart = blob.pos
  var codeOffsets = initTable[tuple[class: Type, name: string, proto: Prototype], uint32]()
  for c in dex.classes:
    let cd = c.class_data
    for dm in cd.direct_methods & cd.virtual_methods:
      if dm.code.kind == MaybeCodeKind.SomeCode:
        inc(codeItems)
        let code = dm.code.code
        codeOffsets[dm.m.asTuple] = blob.pos
        blob.put16(code.registers)
        blob.put16(code.ins)
        blob.put16(code.outs)
        blob.put16(0'u16)  # TODO: tries_size
        blob.put32(0'u32)  # TODO: debug_info_off
        let slot = blob.slot32() # This shall be filled with size of instrs, in 16-bit code units
        dex.renderInstrs(blob, code.instrs, stringIds)
        blob.set(slot, (blob.pos - slot.uint32 - 4) div 2)
  if codeItems > 0'u32:
    sectionOffsets.add((0x2001'u16, codeItems, codeOffset))
  #-- Render type lists
  blob.pad32()
  if dex.typeLists.len > 0:
    sectionOffsets.add((0x1001'u16, dex.typeLists.len.uint32, blob.pos))
  for l in dex.typeLists:
    blob.pad32()
    typeListOffsets.setAll(l, blob.pos, blob)
    blob.put32(l.len.uint32)
    for t in l:
      blob.put16(dex.types.search(t).uint16)
  #-- Render strings data
  sectionOffsets.add((0x2002'u16, dex.strings.len.uint32, blob.pos))
  for s in dex.stringsAsAdded:
    let slot = stringOffsets[stringIds[dex.strings[s]]]
    blob.set(slot, blob.pos)
    # FIXME: MUTF-8: encode U+0000 as hex: C0 80
    # FIXME: MUTF-8: use CESU-8 to encode code-points from beneath Basic Multilingual Plane (> U+FFFF)
    # FIXME: length *in UTF-16 code units*, as ULEB128
    blob.put_uleb128(s.len.uint32)
    blob.puts(s & "\x00")
  #-- Render class data
  sectionOffsets.add((0x2000'u16, dex.classes.len.uint32, blob.pos))
  for c in dex.classes:
    classDataOffsets.setAll(c.class, blob.pos, blob)
    let d = c.class_data
    blob.put_uleb128(0)  # TODO: static_fields_size
    blob.put_uleb128(0)  # TODO: instance_fields_size
    blob.put_uleb128(d.direct_methods.len.uint32)
    blob.put_uleb128(d.virtual_methods.len.uint32)
    # TODO: static_fields
    # TODO: instance_fields
    dex.renderEncodedMethods(blob, d.direct_methods, codeOffsets)
    dex.renderEncodedMethods(blob, d.virtual_methods, codeOffsets)
  #-- Render map_list
  blob.pad32()
  sectionOffsets.add((0x1000'u16, 1'u32, blob.pos))
  blob.set(mapOffsetSlot, blob.pos)
  blob.put32(sectionOffsets.len.uint32)
  for s in sectionOffsets:
    blob.put16(s.typ)
    blob.reserve(2)  # unused
    blob.put32(s.size)
    blob.put32(s.offset)

  #-- Fill remaining slots related to file size
  blob.set(dataSizeSlot, blob.pos - dataStart)  # FIXME: round to 64?
  blob.set(fileSizeSlot, blob.pos)
  #-- Fill checksums
  let sha1 = secureHash(blob.string.substr(0x20))
  let sha1sum = parseHexStr($sha1)  # FIXME(akavel): should not have to go through string!
  for i in 0 ..< 20:
    blob.string[0x0c + i] = sha1sum[i]
  blob.set(adlerSumSlot, adler32(blob.string.substr(0x0c)))
  return blob.string


proc collect(dex: Dex) =
  # Collect strings and all the things from classes.
  # (types, prototypes/signatures, fields, methods)
  for c in dex.classes:
    dex.addType(c.class)
    if c.superclass.kind == MaybeTypeKind.SomeType:
      dex.addType(c.superclass.typ)
    let cd = c.class_data
    for dm in cd.direct_methods & cd.virtual_methods:
      dex.addMethod(dm.m)
      if dm.code.kind == MaybeCodeKind.SomeCode:
        for instr in dm.code.code.instrs:
          for arg in instr.args:
            match arg:
              RawX(r): discard
              RawXX(r): discard
              RawXXXX(r): discard
              RegX(r): discard
              RegXX(r): discard
              FieldXXXX(f):
                dex.addField(f)
              StringXXXX(s):
                dex.addStr(s)
              TypeXXXX(t):
                dex.addType(t)
              MethodXXXX(m):
                dex.addMethod(m)

proc renderEncodedMethods(dex: Dex, blob: var Blob, methods: openArray[EncodedMethod], codeOffsets: Table[tuple[class: Type, name: string, proto: Prototype], uint32]) =
  var prev = 0
  for m in methods:
    let tupl = m.m.asTuple
    let idx = dex.methods.search(tupl)
    blob.put_uleb128(uint32(idx - prev))
    prev = idx
    blob.put_uleb128(m.access.toUint32)
    if Native notin m.access and Abstract notin m.access:
      blob.put_uleb128(codeOffsets[tupl])
    else:
      blob.put_uleb128(0)

proc renderInstrs(dex: Dex, blob: var Blob, instrs: openArray[Instr], stringIds: openArray[int]) =
  var
    high = true
  for instr in instrs:
    blob.putc(instr.opcode.chr)
    for arg in instr.args:
      # FIXME(akavel): padding
      match arg:
        RawX(v):
          blob.put4(v, high)
          high = not high
        RawXX(v):
          blob.putc(v.chr)
        RawXXXX(v):
          blob.put16(v)
        RegX(v):
          blob.put4(v, high)
          high = not high
        RegXX(v):
          blob.putc(v.chr)
        FieldXXXX(v):
          blob.put16(dex.fields.search((v.class, v.name, v.typ)).uint16)
        StringXXXX(v):
          blob.put16(stringIds[dex.strings[v]].uint16)
        TypeXXXX(v):
          blob.put16(dex.types.search(v).uint16)
        MethodXXXX(v):
          blob.put16(dex.methods.search((v.class, v.name, v.prototype)).uint16)

proc move_result_object*(reg: uint8): Instr =
  return newInstr(0x0c, RegXX(reg))
proc return_void*(): Instr =
  return newInstr(0x0e, RawXX(0))
proc const_high16*(reg: uint8, highBits: uint16): Instr =
  return newInstr(0x15, RegXX(reg), RawXXXX(highBits))
proc const_string*(reg: uint8, s: String): Instr =
  return newInstr(0x1a, RegXX(reg), StringXXXX(s))
proc new_instance*(reg: uint8, t: Type): Instr =
  return newInstr(0x22, RegXX(reg), TypeXXXX(t))
proc sget_object*(reg: uint8, field: Field): Instr =
  return newInstr(0x62, RegXX(reg), FieldXXXX(field))

proc invoke_virtual*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x6e, regC, m)
proc invoke_virtual*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x6e, regC, regD, m)

proc invoke_super*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x6f, regC, regD, m)

proc invoke_direct*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x70, regC, m)
proc invoke_direct*(regC: uint4, regD: uint4, m: Method): Instr =
  return newInvoke2(0x70, regC, regD, m)

proc invoke_static*(regC: uint4, m: Method): Instr =
  return newInvoke1(0x71, regC, m)


proc newInvoke1(opcode: uint8, regC: uint4, m: Method): Instr =
  return newInstr(opcode, RawX(1), RawX(0), MethodXXXX(m), RawX(0), RegX(regC), RawXX(0))
proc newInvoke2(opcode: uint8, regC: uint4, regD: uint4, m: Method): Instr =
  return newInstr(opcode, RawX(2), RawX(0), MethodXXXX(m), RawX(regD), RegX(regC), RawXX(0))

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
  if ts.len == 0:
    return
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

func asTuple(m: Method): tuple[class: Type, name: string, proto: Prototype] =
  return (class: m.class, name: m.name, proto: m.prototype)

proc adler32(s: string): uint32 =
  # https://en.wikipedia.org/wiki/Adler-32
  var a: uint32 = 1
  var b: uint32 = 0
  const MOD_ADLER = 65521
  for c in s:
    a = (a + c.uint32) mod MOD_ADLER
    b = (b + a) mod MOD_ADLER
  result = (b shl 16) or a
