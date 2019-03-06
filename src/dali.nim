{.experimental: "codeReordering".}
import std/sha1

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
  header.write(0x10, secureHash(header.substr(0x20) & tail))
  # Adler checksum
  header.write(0x08, adler32(header.substr(0x10) & tail))
  return header & tail

proc write(s: var string, pos: int, what: string) =
  if pos + what.len > s.len:
    setLen(s, pos + what.len)
  copyMem(addr(s[pos]), what, what.len)

proc write(s: var string, pos: int, what: uint32) =
  # Little-endian
  let buf = [
    chr(v and 0xff),
    chr(v shr 8 and 0xff),
    chr(v shr 16 and 0xff),
    chr(v shr 24 and 0xff)]
  s.write(pos, buf)

proc adler32(s: string): uint32 =
  var a: uint32 = 1
  var b: uint32 = 0
  const MOD_ADLER = 65521
  for c in s:
    a = (a + c.uint32) % MOD_ADLER
    b = (b + a) % MOD_ADLER
  result = (b shl 16) or a

