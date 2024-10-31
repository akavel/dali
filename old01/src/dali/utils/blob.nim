{.experimental: "codeReordering".}
import bitops
import tables

type
  Blob* = distinct string
  uint4* = range[0..15]   # "nibble" / hex digit / half-byte
  Slot32* = distinct int
  # Slot16* = distinct int

  Slots32*[T] = distinct TSlots32[T]
  TSlots32[T] = Table[T, seq[Slot32]]

proc skip*(b: var Blob, n: int) {.inline.} =
  var s = b.string
  let pos = s.len
  s.setLen(pos + n)
  for i in pos ..< s.len:
    s[i] = chr(0)
  b = s.Blob

template `>>:`*(slot32: Slot32, slot: untyped): untyped =
  let slot = slot32

proc `>>`*(slot32: Slot32, slot: var Slot32) =
  slot = slot32

proc slot32*(b: var Blob): Slot32 {.inline.} =
  result = b.string.len.Slot32
  b.skip(4)

proc set*(b: var Blob, slot: Slot32, v: uint32) =
  let i = slot.int
  # Little-endian
  b.string[i+0] = chr(v and 0xff)
  b.string[i+1] = chr(v shr 8 and 0xff)
  b.string[i+2] = chr(v shr 16 and 0xff)
  b.string[i+3] = chr(v shr 24 and 0xff)

proc `[]=`*(b: var Blob, slot: Slot32, v: uint32) =
  b.set(slot, v)

proc pad32*(b: var Blob) {.inline.} =
  let n = (4 - (b.string.len mod 4)) mod 4
  b.skip(n)

proc puts*(b: var Blob, v: string) =
  if v.len == 0:
    return
  var s = b.string
  let pos = s.len
  s.setLen(pos + v.len)
  when nimvm:
    for i, c in v:
      s[pos+i] = c
  else:
    copyMem(addr(s[pos]), cstring(v), v.len)
  b = s.Blob

proc putc*(b: var Blob, v: char) {.inline.} =
  b.puts($v)

proc put32*(b: var Blob, v: uint32) =
  b.set(b.slot32, v)

proc put32*(b: var Blob): Slot32 =
  b.slot32()

proc put16*(b: var Blob, v: uint16) =
  # Little-endian
  var buf = newString(2)
  buf[0] = chr(v and 0xff)
  buf[1] = chr(v shr 8 and 0xff)
  b.puts(buf)

proc put_uleb128*(b: var Blob, v: uint32) =
  ## Writes an uint32 in ULEB128 format
  ## (https://source.android.com/devices/tech/dalvik/dex-format#leb128)
  if v == 0:
    b.puts("\x00")
    return
  let
    topBit = fastLog2(v)  # position of the highest bit set
    n = topBit div 7 + 1  # number of bytes required for ULEB128 encoding of 'v'
  var
    buf = newString(n.Natural)
    work = v
    i = 0
  while work >= 0x80'u32:
    buf[i] = chr(0x80.byte or (work and 0x7F).byte)
    work = work shr 7
    inc i
  buf[i] = chr(work.byte)
  b.puts(buf)

proc put4*(b: var Blob, v: uint4, high: bool) =
  var s = b.string
  let pos = s.len
  if high:
    s.setLen(pos + 1)
    s[pos] = chr(v.uint8 shl 4)
  else:
    s[pos-1] = chr(s[pos-1].ord.uint8 or v.uint8)
  b = s.Blob

proc pos*(b: var Blob): uint32 {.inline.} =
  return b.string.len.uint32


proc add*[T](slots: var Slots32[T], key: T, val: Slot32) =
  slots.madd(key) = val
proc madd*[T](slots: var Slots32[T], key: T): var Slot32 =
  var s = slots.TSlots32[:T].mgetOrPut(key, newSeq[Slot32]()).addr
  s[].add(0.Slot32)
  s[][^1]

proc setAll*[T](slots: Slots32[T], key: T, val: uint32, blob: var Blob) =
  if not slots.TSlots32[:T].contains(key):
    return
  for slot in slots.TSlots32[:T][key]:
    blob.set(slot, val)

proc len*[T](slots: Slots32[T]): int = slots.TSlots32[:T].len
proc contains*[T](slots: Slots32[T], key: T): bool = slots.TSlots32[:T].contains(key)

