{.experimental: "codeReordering".}
import bitops

type
  Blob* = distinct string
  uint4* = range[0..15]   # "nibble" / hex digit / half-byte
  Slot32* = distinct int
  # Slot16* = distinct int

proc reserve*(b: var Blob, n: int) {.inline.} =
  let pos = b.string.len
  b.string.setLen(pos + n)
  for i in pos ..< b.string.len:
    b.string[i] = chr(0)

proc slot32*(b: var Blob): Slot32 {.inline.} =
  result = b.string.len.Slot32
  b.reserve(4)

proc set*(b: var Blob, slot: Slot32, v: uint32) =
  let i = slot.int
  # Little-endian
  b.string[i+0] = chr(v and 0xff)
  b.string[i+1] = chr(v shr 8 and 0xff)
  b.string[i+2] = chr(v shr 16 and 0xff)
  b.string[i+3] = chr(v shr 24 and 0xff)

proc pad32*(b: var Blob) {.inline.} =
  let n = (4 - (b.string.len mod 4)) mod 4
  b.reserve(n)

proc puts*(b: var Blob, v: string) =
  if v.len == 0:
    return
  var s = b.string
  let pos = s.len
  s.setLen(pos + v.len)
  copyMem(addr(s[pos]), cstring(v), v.len)
  b = s.Blob

proc putc*(b: var Blob, v: char) {.inline.} =
  b.puts($v)

proc put32*(b: var Blob, v: uint32) =
  b.set(b.slot32, v)

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
