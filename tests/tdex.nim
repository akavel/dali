{.experimental: "codeReordering".}
import unittest
import dali

test "hello world.apk":
  # Based on: https://github.com/corkami/pics/blob/master/binary/DalvikEXecutable.pdf
  want = strip_space"""
.d .e .x 0A .0 .3 .5 00  6F 53 89 BC 1E 79 B2 4F
1F 9C 09 66 15 23 2D 3B  56 65 32 C3 B5 81 B4 5A
70 02 00 00 70 00 00 00  78 56 34 12 00 00 00 00
00 00 00 00 DC 01 00 00  0C 00 00 00 70 00 00 00
07 00 00 00 A0 00 00 00  02 00 00 00 BC 00 00 00
01 00 00 00 D4 00 00 00  02 00 00 00 DC 00 00 00
01 00 00 00 EC 00 00 00  64 01 00 00 0C 01 00 00
A6 01 00 00 3A 01 00 00  8A 01 00 00 40 01 00 00
B4 01 00 00 76 01 00 00  54 01 00 00 6C 01 00 00
57 01 00 00 70 01 00 00  A1 01 00 00 C8 01 00 00
01 00 00 00 02 00 00 00  03 00 00 00 04 00 00 00
05 00 00 00 06 00 00 00  08 00 00 00 07 00 00 00
05 00 00 00 34 01 00 00  07 00 00 00 05 00 00 00
2C 01 00 00 04 00 01 00  0A 00 00 00 00 00 01 00
09 00 00 00 01 00 00 00  0B 00 00 00 00 00 00 00
01 00 00 00 02 00 00 00  00 00 00 00 FF FF FF FF
00 00 00 00 D1 01 00 00  00 00 00 00 02 00 01 00
02 00 00 00 00 00 00 00  08 00 00 00 62 00 00 00
1A 01 00 00 6E 20 01 00  10 00 0E 00 01 00 00 00
06 00 00 00 01 00 00 00  03 00 04 .L .h .w .; 00
12 .L .j .a .v .a ./ .l  .a .n .g ./ .O .b .j .e
.c .t .; 00 01 .V 00 13  .[ .L .j .a .v .a ./ .l
.a .n .g ./ .S .t .r .i  .n .g .; 00 02 .V .L 00
04 .m .a .i .n 00 12 .L  .j .a .v .a ./ .l .a .n
.g ./ .S .y .s .t .e .m  .; 00 15 .L .j .a .v .a
./ .i .o ./ .P .r .i .n  .t .S .t .r .e .a .m .;
00 03 .o .u .t 00 0C .H  .e .l .l .o 20 .W .o .r
.l .d .! 00 12 .L .j .a  .v .a ./ .l .a .n .g ./
.S .t .r .i .n .g .; 00  07 .p .r .i .n .t .l .n
00 00 00 01 00 00 09 8C  02 00 00 00 0C 00 00 00
00 00 00 00 01 00 00 00  00 00 00 00 01 00 00 00
0C 00 00 00 70 00 00 00  02 00 00 00 07 00 00 00
A0 00 00 00 03 00 00 00  02 00 00 00 BC 00 00 00
04 00 00 00 01 00 00 00  D4 00 00 00 05 00 00 00
02 00 00 00 DC 00 00 00  06 00 00 00 01 00 00 00
EC 00 00 00 01 20 00 00  01 00 00 00 0C 01 00 00
01 10 00 00 02 00 00 00  2C 01 00 00 02 20 00 00
0C 00 00 00 3A 01 00 00  00 20 00 00 01 00 00 00
D1 01 00 00 00 10 00 00  01 00 00 00 DC 01 00 00
"""
  let tail = want.substr(0x2C * 2).parseHexStr
  let have = sample_dex(tail).hexify
  check have == want

proc strip_space(s: string): string =
  return s.multiReplace(("\n", ""), (" ", ""))

proc hexify(s: string): string =
  # Based on strutils.toHex
  const HexChars = "0123456789ABCDEF"
  result = newString(s.len * 2)
  for pos, c in s:
    let n = ord(c)
    if 0x21 <= n and n <= 0x7E:
      result[pos * 2] = '.'
      result[pos * 2 + 1] = c
    else:
      result[pos * 2] = HexChars[n shr 4]
      result[pos * 2 + 1] = HexChars[n and 0x0F]

