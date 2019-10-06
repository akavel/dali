{.experimental: "codeReordering".}
import critbits
import strutils
import sequtils
import std/sha1
import tables

import patty

import dali/utils/blob
import dali/utils/sortedset

import dali/types

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

#########
# NOTE(akavel): this must be early, to make sure it's used, as codeReordering fails to move it
#########
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
#########
#########

proc newDex*(): Dex =
  new(result)

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


proc render*(dex: Dex): string =
  # stderr.write(dex.repr)
  dex.collect()

  # Storage for offsets where various sections of the file
  # start. Will be needed to render map_list.
  # NOTE: n is number of elements in the section, not length in bytes.
  var sections: seq[tuple[kind: uint16, pos: uint32, n: int]]

  # blob is the buffer where we will render the binary contents of the .dex file
  var blob: Blob

  # slots are places in the blob, where we can't put data immediately. That's
  # because the value that should be there depends on some data further along
  # in the file. We bookmark some space for them in the blob, for filling in
  # later, when we will know what to put in the slot.
  var slots: tuple[
    adlerSum: Slot32,
    fileSize: Slot32,
    mapOffset: Slot32,
    stringIdsOff: Slot32,
    typeIdsOff: Slot32,
    protoIdsOff: Slot32,
    fieldIdsOff: Slot32,
    methodIdsOff: Slot32,
    classDefsOff: Slot32,
    dataSize: Slot32,
    dataOff: Slot32,
    stringOffsets: seq[Slot32],
  ]
  slots.stringOffsets.setLen(dex.strings.len)

  # FIXME: ensure correct padding everywhere

  #-- Partially render header
  # Most of it can only be calculated after the rest of the segments.
  sections.add (0x0000'u16, blob.pos, 1)
  # TODO: handle various versions of targetSdkVersion file, not only 035
  blob.puts  "dex\n035\x00"       # Magic prefix
  blob.put32 >> slots.adlerSum
  blob.skip(20)                   # SHA1 sum; we will fill it much later
  blob.put32 >> slots.fileSize
  blob.put32 0x70                 # Header size
  blob.put32 0x12345678   # Endian constant
  blob.put32 0            # link_size
  blob.put32 0            # link_off
  blob.put32 >> slots.mapOffset
  blob.put32 dex.strings.len.uint32
  blob.put32 >> slots.stringIdsOff
  blob.put32 dex.types.len.uint32
  blob.put32 >> slots.typeIdsOff
  blob.put32 dex.prototypes.len.uint32
  blob.put32 >> slots.protoIdsOff
  blob.put32 dex.fields.len.uint32
  blob.put32 >> slots.fieldIdsOff
  blob.put32 dex.methods.len.uint32
  blob.put32 >> slots.methodIdsOff
  blob.put32 dex.classes.len.uint32
  blob.put32 >> slots.classDefsOff
  blob.put32 >> slots.dataSize
  blob.put32 >> slots.dataOff

  # stderr.write(blob.string.dumpHex)
  # stderr.write("\n")

  # blob.reserve(0x70 - blob.pos.int)

  #-- Partially render string_ids
  # We preallocate space for the list of string offsets. We cannot fill it yet, as its contents
  # will depend on the size of the other segments.
  sections.add (0x0001'u16, blob.pos, dex.strings.len)
  blob[slots.stringIdsOff] = blob.pos
  for i in 0 ..< dex.strings.len:
    blob.put32 >> slots.stringOffsets[i]

  # stderr.write(blob.string.dumpHex)
  # stderr.write("\n")

  #-- Render typeIDs.
  sections.add (0x0002'u16, blob.pos, dex.types.len)
  blob[slots.typeIdsOff] = blob.pos
  let stringIds = dex.stringsOrdering
  # dex.types are already stored sorted, same as dex.strings, so we don't need
  # to sort again by type IDs
  for t in dex.types:
    blob.put32 stringIds[dex.strings[t]].uint32

  #-- Partially render proto IDs.
  # We cannot fill offsets for parameters (type lists), as they'll depend on the size of the
  # segments inbetween.
  sections.add (0x0003'u16, blob.pos, dex.prototypes.len)
  blob[slots.protoIdsOff] = blob.pos
  var typeListOffsets: Slots32[seq[Type]]
  for p in dex.prototypes:
    blob.put32 stringIds[dex.strings[p.descriptor]].uint32
    blob.put32 dex.types.search(p.ret).uint32
    blob.put32 >>: slot
    typeListOffsets.add(p.params, slot)
    # echo p.ret, " ", p.params

  #-- Render field IDs
  if dex.fields.len > 0:
    sections.add (0x0004'u16, blob.pos, dex.fields.len)
    blob[slots.fieldIdsOff] = blob.pos
  for f in dex.fields:
    blob.put16 dex.types.search(f.class).uint16
    blob.put16 dex.types.search(f.typ).uint16
    blob.put32 stringIds[dex.strings[f.name]].uint32

  #-- Render method IDs
  sections.add (0x0005'u16, blob.pos, dex.methods.len)
  if dex.methods.len > 0:
    blob[slots.methodIdsOff] = blob.pos
  for m in dex.methods:
    # echo $m
    blob.put16 dex.types.search(m.class).uint16
    blob.put16 dex.prototypes.search(m.proto).uint16
    blob.put32 stringIds[dex.strings[m.name]].uint32

  #-- Partially render class defs.
  sections.add (0x0006'u16, blob.pos, dex.classes.len)
  blob[slots.classDefsOff] = blob.pos
  var classDataOffsets: Slots32[Type]
  const NO_INDEX = 0xffff_ffff'u32
  for c in dex.classes:
    blob.put32 dex.types.search(c.class).uint32
    blob.put32 c.access.uint32
    match c.superclass:
      SomeType(t):
        blob.put32 dex.types.search(t).uint32
      NoType:
        blob.put32 NO_INDEX
    blob.put32 0'u32      # TODO: interfaces_off
    blob.put32 NO_INDEX   # TODO: source_file_idx
    blob.put32 0'u32      # TODO: annotations_off
    blob.put32 >>: slot
    classDataOffsets.add(c.class, slot)
    blob.put32 0'u32      # TODO: static_values

  #-- Render code items
  let dataStart = blob.pos
  blob[slots.dataOff] = dataStart
  var
    codeItems = 0
    codeOffsets: Table[tuple[class: Type, name: string, proto: Prototype], uint32]
  for c in dex.classes:
    let cd = c.class_data
    for dm in cd.direct_methods & cd.virtual_methods:
      if dm.code.kind == MaybeCodeKind.SomeCode:
        codeItems.inc()
        let code = dm.code.code
        codeOffsets[dm.m.asTuple] = blob.pos
        blob.put16 code.registers
        blob.put16 code.ins
        blob.put16 code.outs
        blob.put16 0'u16   # TODO: tries_size
        blob.put32 0'u32   # TODO: debug_info_off
        blob.put32 >>: slot   # This shall be filled with size of instrs, in 16-bit code units
        dex.renderInstrs(blob, code.instrs, stringIds)
        blob[slot] = (blob.pos - slot.uint32 - 4) div 2
  if codeItems > 0:
    sections.add (0x2001'u16, dataStart, codeItems)

  #-- Render type lists
  blob.pad32()
  if dex.typeLists.len > 0:
    sections.add (0x1001'u16, blob.pos, dex.typeLists.len)
  for l in dex.typeLists:
    blob.pad32()
    typeListOffsets.setAll(l, blob.pos, blob)
    blob.put32 l.len.uint32
    for t in l:
      blob.put16 dex.types.search(t).uint16

  #-- Render strings data
  sections.add (0x2002'u16, blob.pos, dex.strings.len)
  for s in dex.stringsAsAdded:
    let slot = slots.stringOffsets[stringIds[dex.strings[s]]]
    blob[slot] = blob.pos
    # FIXME: MUTF-8: encode U+0000 as hex: C0 80
    # FIXME: MUTF-8: use CESU-8 to encode code-points from beneath Basic Multilingual Plane (> U+FFFF)
    # FIXME: length *in UTF-16 code units*, as ULEB128
    blob.put_uleb128 s.len.uint32
    blob.puts s & "\x00"

  #-- Render class data
  sections.add (0x2000'u16, blob.pos, dex.classes.len)
  for c in dex.classes:
    classDataOffsets.setAll(c.class, blob.pos, blob)
    let d = c.class_data
    blob.put_uleb128 0  # TODO: static_fields_size
    blob.put_uleb128 0  # TODO: instance_fields_size
    blob.put_uleb128 d.direct_methods.len.uint32
    blob.put_uleb128 d.virtual_methods.len.uint32
    # TODO: static_fields
    # TODO: instance_fields
    dex.renderEncodedMethods(blob, d.direct_methods, codeOffsets)
    dex.renderEncodedMethods(blob, d.virtual_methods, codeOffsets)

  #-- Render map_list
  blob.pad32()
  sections.add (0x1000'u16, blob.pos, 1)
  blob[slots.mapOffset] = blob.pos
  blob.put32 sections.len.uint32
  for s in sections:
    blob.put16 s.kind
    blob.skip(2)   # unused
    blob.put32 s.n.uint32
    blob.put32 s.pos

  #-- Fill remaining slots related to file size
  blob[slots.dataSize] = blob.pos - dataStart  # FIXME: round to 64?
  blob[slots.fileSize] = blob.pos
  #-- Fill checksums
  let sha1 = secureHash(blob.string.substr(0x20)).Sha1Digest
  for i in 0 ..< 20:
    blob.string[0x0c + i] = sha1[i].char
  blob[slots.adlerSum] = adler32(blob.string.substr(0x0c))
  # stderr.write(blob.string.dumpHex)
  # stderr.write("\n")

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
              RawX(_): discard
              RawXX(_): discard
              RawXXXX(_): discard
              RegX(_): discard
              RegXX(_): discard
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
    blob.put_uleb128 uint32(idx - prev)
    prev = idx
    blob.put_uleb128 m.access.toUint32
    if Native notin m.access and Abstract notin m.access:
      blob.put_uleb128 codeOffsets[tupl]
    else:
      blob.put_uleb128 0

proc renderInstrs(dex: Dex, blob: var Blob, instrs: openArray[Instr], stringIds: openArray[int]) =
  var
    high = true
  for instr in instrs:
    blob.putc instr.opcode.chr
    for arg in instr.args:
      # FIXME(akavel): padding
      match arg:
        RawX(v):
          blob.put4 v, high
          high = not high
        RawXX(v):
          blob.putc v.chr
        RawXXXX(v):
          blob.put16 v
        RegX(v):
          blob.put4 v, high
          high = not high
        RegXX(v):
          blob.putc v.chr
        FieldXXXX(v):
          blob.put16 dex.fields.search((v.class, v.name, v.typ)).uint16
        StringXXXX(v):
          blob.put16 stringIds[dex.strings[v]].uint16
        TypeXXXX(v):
          blob.put16 dex.types.search(v).uint16
        MethodXXXX(v):
          blob.put16 dex.methods.search((v.class, v.name, v.prototype)).uint16


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
    if t.len==1 and t[0] in {'V','Z','B','S','C','I','J','F','D'}:
      return t
    elif t.len>=1 and t[0] in {'[','L'}:
      return "L"
    else:
      raise newException(ConsistencyError, "unexpected type in prototype: " & t)

  return (proto.ret & proto.params).map(typeChar).join

proc addTypeList(dex: Dex, ts: seq[Type]) =
  if ts.len == 0:
    return
  for t in ts:
    dex.addType(t)
  if ts notin dex.typeLists:
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
  result.setLen dex.strings.len
  for s, added in dex.strings:
    result[added] = i
    inc i

proc stringsAsAdded(dex: Dex): seq[string] =
  result.setLen dex.strings.len
  for s, added in dex.strings:
    result[added] = s

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

