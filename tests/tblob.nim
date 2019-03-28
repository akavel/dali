{.experimental: "codeReordering".}
import unittest
import strutils
import dali/blob

test "reserve":
  var s = "".Blob
  s.reserve(4)
  check s.string.toHex == strip_space"00 00 00 00"

test "puts":
  var s = "".Blob
  s.puts("hello ")
  s.puts("world")
  check s.string == "hello world"

test "put32 little endian":
  var s = "".Blob
  s.put32(0x1234_5678)
  check s.string.toHex == strip_space"78 56 34 12"

test "put16 little endian x2":
  var s = "".Blob
  s.put16(0x1234)
  s.put16(0x5678)
  check s.string.toHex == strip_space"34 12 78 56"

test "put_uleb128":
  proc uleb128(n: uint32): string =
    var s = "".Blob
    s.put_uleb128(n)
    return s.string
  check uleb128(0).toHex == strip_space"00"
  check uleb128(1).toHex == strip_space"01"
  check uleb128(127).toHex == strip_space"7F"
  check uleb128(16256).toHex == strip_space"80 7F"

test "put4":
  var s = "".Blob
  s.put4(0xf, true)
  s.put4(0xa, false)
  s.put4(0x1, true)
  s.put4(0x2, false)
  check s.string.toHex == strip_space"FA 12"

proc strip_space(s: string): string =
  return s.multiReplace(("\n", ""), (" ", ""))
