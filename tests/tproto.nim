import unittest
import dali

# dumpTree:
#   Method(
#     class: HelloActivity,
#     name: "<init>",
#     prototype: Prototype(ret: "V", params: @[1,2,3]),
#   )

# echo "runtime"
#
let
  hello = "Lcom/hello/Hello;"
  z = "Lfoo/bar/Z;"
  zz = "Lfoo/bar/Zz;"
  zzz = "Lfoo/bar/Zzz;"
  View = "Landroid/view/View;"
  h1 = jproto hello.world()
  h2 = jproto hello.world(z, zz, int): zzz
  # jproto hello.world(z, zz, int): zzz[int, float]
  h4 = jproto hello.`<init>`()
  # jproto hello.<init>()
  # jproto hello.world(z: y): zzz[int, float]
  # jproto hello.world(z: y, one: two): zzz[int, float]
  # jproto(hello.world(z: y): zzz)

let
  HelloActivity = "Lfoo/HelloActivity;"
  String = "Ljava/lang/String;"

test "long prototype syntax":
  let p = jproto HelloActivity.setContentView(View, int): String
  checkpoint p.repr
  check p.equals Method(
    class: HelloActivity,
    name: "setContentView",
    prototype: Prototype(ret: String, params: @[View, "I"]))

test "short prototype syntax":
  let p = jproto HelloActivity.foo()
  checkpoint p.repr
  check p.equals Method(
    class: HelloActivity,
    name: "foo",
    prototype: Prototype(ret: "V", params: @[]))

test "constructor":
  let p = jproto HelloActivity.`<init>`()
  checkpoint p.repr
  check p.equals Method(
    class: HelloActivity,
    name: "<init>",
    prototype: Prototype(ret: "V", params: @[]))
