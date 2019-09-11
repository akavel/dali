{.experimental: "codeReordering".}
import unittest
import strutils
include dali

suite "internals":
  test "write_uleb128":
    proc uleb128(n: uint32): string =
      var s = ""
      discard s.write_uleb128(0, n)
      return s
    check uleb128(0).toHex == strip_space"00"
    check uleb128(1).toHex == strip_space"01"
    check uleb128(127).toHex == strip_space"7F"
    check uleb128(16256).toHex == strip_space"80 7F"

  test "renderStringsAndOffsets unsorted":
    var dex = newDex()
    dex.addStr"Lhw;"
    dex.addStr"Ljava/lang/Object;"
    dex.addStr"V"
    dex.addStr"[Ljava/lang/String;"
    dex.addStr"VL"
    dex.addStr"main"
    dex.addStr"Ljava/lang/System;"
    dex.addStr"Ljava/io/PrintStream;"
    dex.addStr"out"
    dex.addStr"Hello World!"
    dex.addStr"Ljava/lang/String;"
    dex.addStr"println"
    let want = strip_space"""
                               04 .L .h .w .; 00
12 .L .j .a .v .a ./ .l  .a .n .g ./ .O .b .j .e
.c .t .; 00 01 .V 00 13  .[ .L .j .a .v .a ./ .l
.a .n .g ./ .S .t .r .i  .n .g .; 00 02 .V .L 00
04 .m .a .i .n 00 12 .L  .j .a .v .a ./ .l .a .n
.g ./ .S .y .s .t .e .m  .; 00 15 .L .j .a .v .a
./ .i .o ./ .P .r .i .n  .t .S .t .r .e .a .m .;
00 03 .o .u .t 00 0C .H  .e .l .l .o 20 .W .o .r
.l .d .! 00 12 .L .j .a  .v .a ./ .l .a .n .g ./
.S .t .r .i .n .g .; 00  07 .p .r .i .n .t .l .n
00""".dehexify
    let (have, offsets) = dex.renderStringsAndOffsets(0x13A)
    check have.dumpHex == want.dumpHex
    let wantOffsets = strip_space"""
A6 01 00 00 3A 01 00 00  8A 01 00 00 40 01 00 00
B4 01 00 00 76 01 00 00  54 01 00 00 6C 01 00 00
57 01 00 00 70 01 00 00  A1 01 00 00 C8 01 00 00
""".dehexify
    check offsets.dumpHex == wantOffsets.dumpHex

  test "renderStringsAndOffsets":
    var dex = newDex()
    dex.addStr"<init>"
    dex.addStr"Landroid/app/Application;"
    dex.addStr"Lcom/bugsnag/dexexample/BugsnagApp;"
    dex.addStr"V"
    dex.addStr"""~~D8{"min-api":26,"version":"v0.1.14"}"""
    let want = strip_space"""
                           063C696E 69743E00 194C616E
64726F69 642F6170 702F4170 706C6963 6174696F 6E3B0023
4C636F6D 2F627567 736E6167 2F646578 6578616D 706C652F
42756773 6E616741 70703B00 01560026 7E7E4438 7B226D69
6E2D6170 69223A32 362C2276 65727369 6F6E223A 2276302E
312E3134 227D00
""".dehexify
    let (have, offsets) = dex.renderStringsAndOffsets(228)
    check have.dumpHex == want.dumpHex
    check offsets.dumpHex == strip_space"""
E4000000 EC000000 07010000 2C010000 2F010000""".dehexify.dumpHex

let hello_world_apk = strip_space"""
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
""".dehexify


test "synthesized hello_world.apk":
  let dex = newDex()
  dex.classes.add(ClassDef(
    class: "Lhw;",
    access: {Public},
    superclass: SomeType("Ljava/lang/Object;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lhw;",
            name: "main",
            prototype: Prototype(
              ret: "V",
              params: @["[Ljava/lang/String;"]),
          ),
          access: {Public, Static},
          code: SomeCode(Code(
            registers: 2,
            ins: 1,
            outs: 2,
            instrs: @[
              sget_object(0, Field(class: "Ljava/lang/System;", typ: "Ljava/io/PrintStream;", name: "out")),
              const_string(1, "Hello World!"),
              invoke_virtual(0, 1, Method(class: "Ljava/io/PrintStream;", name: "println",
                prototype: Prototype(ret: "V", params: @["Ljava/lang/String;"]))),
              return_void(),
            ]))
        )
      ]
    )
  ))
  check dex.render.dumpHex == hello_world_apk.dumpHex

test "synthesized hello_world.apk prettified with macros":
  let
    dex = newDex()
    PrintStream = "Ljava/io/PrintStream;"
    String = "Ljava/lang/String;"
  dex.classes.add(ClassDef(
    class: "Lhw;",
    access: {Public},
    superclass: SomeType("Ljava/lang/Object;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lhw;",
            name: "main",
            prototype: Prototype(
              ret: "V",
              params: @["[Ljava/lang/String;"]),
          ),
          access: {Public, Static},
          code: SomeCode(Code(
            registers: 2,
            ins: 1,
            outs: 2,
            instrs: @[
              sget_object(0, Field(class: "Ljava/lang/System;", typ: "Ljava/io/PrintStream;", name: "out")),
              const_string(1, "Hello World!"),
              invoke_virtual(0, 1, jproto PrintStream.println(String)),
              return_void(),
            ]))
        )
      ]
    )
  ))
  check dex.render.dumpHex == hello_world_apk.dumpHex

test "hello world.apk":
  # Based on: https://github.com/corkami/pics/blob/master/binary/DalvikEXecutable.pdf
  let want = hello_world_apk
  let tail = want.substr(0x2C)
  let have = sample_dex(tail)
  # check have.hexify == want.hexify
  # check have.toHex == want.toHex
  check have.dumpHex == want.dumpHex

let bugsnag_sample_apk = strip_space"""
6465780A 30333800 7A44CBBB FB4AE841 0286C06A 8DF19000
3C5DE024 D07326A2 E0010000 70000000 78563412 00000000
00000000 64010000 05000000 70000000 03000000 84000000
01000000 90000000 00000000 00000000 02000000 9C000000
01000000 AC000000 14010000 CC000000 E4000000 EC000000
07010000 2C010000 2F010000 01000000 02000000 03000000
03000000 02000000 00000000 00000000 00000000 01000000
00000000 01000000 01000000 00000000 00000000 FFFFFFFF
00000000 57010000 00000000 01000100 01000000 00000000
04000000 70100000 00000E00 063C696E 69743E00 194C616E
64726F69 642F6170 702F4170 706C6963 6174696F 6E3B0023
4C636F6D 2F627567 736E6167 2F646578 6578616D 706C652F
42756773 6E616741 70703B00 01560026 7E7E4438 7B226D69
6E2D6170 69223A32 362C2276 65727369 6F6E223A 2276302E
312E3134 227D0000 00010001 818004CC 01000000 0A000000
00000000 01000000 00000000 01000000 05000000 70000000
02000000 03000000 84000000 03000000 01000000 90000000
05000000 02000000 9C000000 06000000 01000000 AC000000
01200000 01000000 CC000000 02200000 05000000 E4000000
00200000 01000000 57010000 00100000 01000000 64010000
""".dehexify

test "synthesized bugsnag.apk (FIXME: except checksums)":
  let dex = newDex()
  #-- Prime some strings, to make sure their order matches bugsnag_sample_apk
  dex.addStr"<init>"
  dex.addStr"Landroid/app/Application;"
  dex.addStr"Lcom/bugsnag/dexexample/BugsnagApp;"
  dex.addStr"V"
  dex.addStr"""~~D8{"min-api":26,"version":"v0.1.14"}"""
  dex.classes.add(ClassDef(
    class: "Lcom/bugsnag/dexexample/BugsnagApp;",
    access: {Public}, # TODO
    superclass: SomeType("Landroid/app/Application;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/bugsnag/dexexample/BugsnagApp;",
            name: "<init>",
            prototype: Prototype(
              ret: "V",
              params: @[],
            ),
          ),
          access: {Public, Constructor},
          code: SomeCode(Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Application;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          )),
        )
      ]
    )
  ))
  # check dex.render.tweak_prefix("dex\x0a038").dumpHex == bugsnag_sample_apk.dumpHex
  # FIXME(akavel): don't know why, but the SHA1 sum in bugsnag_sample_apk seems incorrect (!)
  check dex.render.substr(0x20).dumpHex == bugsnag_sample_apk.substr(0x20).dumpHex

test "synthesized bugsnag.apk (FIXME: except checksums) prettified with macros":
  let
    dex = newDex()
    BugsnagApp = "Lcom/bugsnag/dexexample/BugsnagApp;"
    Application = "Landroid/app/Application;"

  #-- Prime some strings, to make sure their order matches bugsnag_sample_apk
  dex.addStr "<init>"
  dex.addStr Application
  dex.addStr BugsnagApp
  dex.addStr "V"
  dex.addStr """~~D8{"min-api":26,"version":"v0.1.14"}"""

  dex.classes.add:
    jclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Application.`<init>`())
        return_void()

  # check dex.render.tweak_prefix("dex\x0a038").dumpHex == bugsnag_sample_apk.dumpHex
  # FIXME(akavel): don't know why, but the SHA1 sum in bugsnag_sample_apk seems incorrect (!)
  check dex.render.substr(0x20).dumpHex == bugsnag_sample_apk.substr(0x20).dumpHex

let hello_android_apk = strip_space"""
6465 780a 3033 3500 2f4f 153b 3623 8747
6d02 4697 5b1e 959d a8b1 2f0f 9c3a a14f
7802 0000 7000 0000 7856 3412 0000 0000
0000 0000 f001 0000 0a00 0000 7000 0000
0500 0000 9800 0000 0300 0000 ac00 0000
0000 0000 0000 0000 0500 0000 d000 0000
0100 0000 f800 0000 6001 0000 1801 0000
6201 0000 6a01 0000 6d01 0000 8501 0000
9a01 0000 bc01 0000 bf01 0000 c301 0000
c701 0000 d101 0000 0100 0000 0200 0000
0300 0000 0400 0000 0500 0000 0500 0000
0400 0000 0000 0000 0600 0000 0400 0000
5401 0000 0700 0000 0400 0000 5c01 0000
0100 0000 0000 0000 0100 0200 0800 0000
0300 0000 0000 0000 0300 0200 0800 0000
0300 0100 0900 0000 0300 0000 0100 0000
0100 0000 0000 0000 ffff ffff 0000 0000
e101 0000 0000 0000 0100 0100 0100 0000
0000 0000 0400 0000 7010 0000 0000 0e00
0300 0200 0200 0000 0000 0000 0900 0000
6f20 0100 2100 1500 037f 6e20 0400 0100
0e00 0000 0100 0000 0000 0000 0100 0000
0200 063c 696e 6974 3e00 0149 0016 4c61
6e64 726f 6964 2f61 7070 2f41 6374 6976
6974 793b 0013 4c61 6e64 726f 6964 2f6f
732f 4275 6e64 6c65 3b00 204c 636f 6d2f
616e 6472 6f69 642f 6865 6c6c 6f2f 4865
6c6c 6f41 6e64 726f 6964 3b00 0156 0002
5649 0002 564c 0008 6f6e 4372 6561 7465
000e 7365 7443 6f6e 7465 6e74 5669 6577
0000 0001 0102 8180 0498 0203 01b0 0200
0b00 0000 0000 0000 0100 0000 0000 0000
0100 0000 0a00 0000 7000 0000 0200 0000
0500 0000 9800 0000 0300 0000 0300 0000
ac00 0000 0500 0000 0500 0000 d000 0000
0600 0000 0100 0000 f800 0000 0120 0000
0200 0000 1801 0000 0110 0000 0200 0000
5401 0000 0220 0000 0a00 0000 6201 0000
0020 0000 0100 0000 e101 0000 0010 0000
0100 0000 f001 0000
""".dehexify

test "synthesized hello_android.apk":
  let dex = newDex()
  #-- Prime some arrays, to make sure their order matches hello_android_apk
  dex.addStr"<init>"
  dex.addStr"I"
  dex.addStr"Landroid/app/Activity;"
  dex.addStr"Landroid/os/Bundle;"
  dex.addStr"Lcom/android/hello/HelloAndroid;"
  dex.addStr"V"
  dex.addStr"VI"
  dex.addStr"VL"
  dex.addStr"onCreate"
  dex.addStr"setContentView"
  dex.addTypeList(@["I"])

  dex.classes.add(ClassDef(
    class: "Lcom/android/hello/HelloAndroid;",
    access: {Public},
    superclass: SomeType("Landroid/app/Activity;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/android/hello/HelloAndroid;",
            name: "<init>",
            prototype: Prototype(ret: "V", params: @[]),
          ),
          access: {Public, Constructor},
          code: SomeCode(Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Activity;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          )),
        ),
      ],
      virtual_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/android/hello/HelloAndroid;",
            name: "onCreate",
            prototype: Prototype(
              ret: "V",
              params: @["Landroid/os/Bundle;"],
            ),
          ),
          access: {Public},
          code: SomeCode(Code(
            registers: 3,
            ins: 2,
            outs: 2,
            instrs: @[
              invoke_super(1, 2, Method(class: "Landroid/app/Activity;", name: "onCreate",
                prototype: Prototype(ret: "V", params: @["Landroid/os/Bundle;"]))),
              const_high16(0, 0x7f03),
              invoke_virtual(1, 0, Method(class: "Lcom/android/hello/HelloAndroid;", name: "setContentView",
                prototype: Prototype(ret: "V", params: @["I"]))),
              return_void(),
            ],
          )),
        ),
      ],
    )
  ))
  check dex.render.dumpHex == hello_android_apk.dumpHex

test "synthesized hello_android.apk prettified with macros":
  let
    dex = newDex()
    HelloAndroid = "Lcom/android/hello/HelloAndroid;"
    Activity = "Landroid/app/Activity;"
    Bundle = "Landroid/os/Bundle;"
  #-- Prime some arrays, to make sure their order matches hello_android_apk
  dex.addStr "<init>"
  dex.addStr "I"
  dex.addStr Activity
  dex.addStr Bundle
  dex.addStr HelloAndroid
  dex.addStr "V"
  dex.addStr "VI"
  dex.addStr "VL"
  dex.addStr "onCreate"
  dex.addStr "setContentView"
  dex.addTypeList(@["I"])

  dex.classes.add:
    jclass com.android.hello.HelloAndroid {.public.} of Activity:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Activity.`<init>`())
        return_void()
      proc onCreate(Bundle) {.public, regs:3, ins:2, outs:2.} =
        invoke_super(1, 2, jproto Activity.onCreate(Bundle))
        const_high16(0, 0x7f03)
        invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
        return_void()

  check dex.render.dumpHex == hello_android_apk.dumpHex

proc tweak_prefix(s, prefix: string): string =
  return prefix & s.substr(prefix.len)

proc strip_space(s: string): string =
  return s.multiReplace(("\n", ""), (" ", ""))

const HexChars = "0123456789ABCDEF"

func printable(c: char): bool =
  let n = ord(c)
  return 0x21 <= n and n <= 0x7E

proc hexify(s: string): string =
  # Based on strutils.toHex
  result = newString(s.len * 2)
  for pos, c in s:
    if printable(c):
      result[pos * 2] = '.'
      result[pos * 2 + 1] = c
    else:
      let n = ord(c)
      result[pos * 2] = HexChars[n shr 4]
      result[pos * 2 + 1] = HexChars[n and 0x0F]

proc dehexify(s: string): string =
  result = newString(s.len div 2)
  for i in 0 ..< s.len div 2:
    let chunk = s.substr(2 * i, 2 * i + 1)
    if chunk[0] == '.':
      result[i] = chunk[1]
    else:
      result[i] = parseHexStr(chunk)[0]

proc dumpHex(s: string): string =
  if s.len == 0: return ""
  let nlines = (s.len + 15) div 16
  const
    left = 3*8 + 2 + 3*8 + 2
    right = 16
    line = left+right+1
  result = ' '.repeat(nlines*line)
  for i, ch in s:
    let
      y = i div 16
      xr = i mod 16
      xl = if xr < 8: 3*xr else: 3*xr + 1
      n = ord(ch)
    result[y*line + xl] = HexChars[n shr 4]
    result[y*line + xl + 1] = HexChars[n and 0x0F]
    result[y*line + left + xr - 1] = if printable(ch): ch else: '.'
    if xr == 0:
      result[y*line + left + right - 1] = '\n'
  result = "\n " & result

