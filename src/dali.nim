{.experimental: "codeReordering".}
import strutils
import critbits
import bitops
import std/sha1

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

type
  Dex* = ref object
    strings: CritBitTree[int]
  NotImplementedYetError* = object of CatchableError

proc newDex*(): Dex =
  new(result)

proc addStr*(dex: Dex, s: string) =
  if s.contains({'\x00', '\x80'..'\xFF'}):
    raise newException(NotImplementedYetError, "strings with 0x00 or 0x80..0xFF bytes are not yet supported")
  discard dex.strings.containsOrIncl(s, dex.strings.len)
  # "This list must be sorted by string contents, using UTF-16 code point
  # values (not in a locale-sensitive manner), and it must not contain any
  # duplicate entries." [dex-format] <- I think this is guaranteed by UTF-8 + CritBitTree type
  # FIXME: MUTF-8: encode U+0000 as hex: C0 80
  # FIXME: MUTF-8: use CESU-8 to encode code-points from beneath Basic Multilingual Plane (> U+FFFF)
  # FIXME: start: length in UTF-16 code units, as ULEB128

proc sample_dex*(tail: string): string =
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

proc write(s: var string, pos: int, what: string) =
  if pos + what.len > s.len:
    setLen(s, pos + what.len)
  copyMem(addr(s[pos]), cstring(what), what.len)

proc write(s: var string, pos: int, what: uint32) =
  # Little-endian
  var buf = newString(4)
  buf[0] = chr(what and 0xff)
  buf[1] = chr(what shr 8 and 0xff)
  buf[2] = chr(what shr 16 and 0xff)
  buf[3] = chr(what shr 24 and 0xff)
  s.write(pos, buf)

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

