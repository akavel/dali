import unittest
import macros
import dali

proc typeCode(humanReadable: string): string =
  case humanReadable
  of "void": "V"
  of "boolean": "Z"
  of "byte": "B"
  of "char": "C"
  of "int": "I"
  of "long": "J"
  of "float": "F"
  of "double": "D"
  else: ""

macro jproto(proto: untyped, ret: untyped = void): untyped =
  ## jproto is a macro converting a prototype declaration into a dali Method object.
  ## Example:
  ##
  ##   let HelloWorld = "Lcom/hello/HelloWorld;"
  ##   let String = "Ljava/lang/String;"
  ##   jproc HelloWorld.hello(String, int): String
  ##   jproc HelloWorld.`<init>`()
  ##   # NOTE: jproc argument must not be parenthesized; the following will not work:
  ##   # jproc(HelloWorld.hello(String, int): String)
  ##
  ## TODO: support Java array types, i.e. int[], int[][], etc.
  # echo proto.treeRepr
  # echo ret.treeRepr
  result = nnkStmtList.newTree()
  # echo "----------------"

  # Verify that proto + ret have correct syntax
  # ...class & method name:
  if proto.kind != nnkCall:
    error "jproto expects a method declaration as an argument", proto
  if proto.len == 0:
    error "jproto expects a method declaration of length 1+ as an argument", proto
  if proto[0].kind != nnkDotExpr:
    error "jproto expects dot-separated class & method name in the argument", proto[0]
  if proto[0].len != 2 or
    proto[0][0].kind != nnkIdent or
    proto[0][1].kind notin {nnkIdent, nnkAccQuoted}:
    error "jproto expects exactly 2 dot-separated names in the argument", proto[0]
  # ... parameters list:
  for i in 1..<proto.len:
    if proto[i].kind != nnkIdent:
      error "jproto expects type names as method parameters", proto[i]
  # ... optional return type:
  if (ret.kind != nnkStmtList or ret.len != 1 or ret[0].kind != nnkIdent) and
    (ret.kind != nnkSym or ret.strVal != "void"):
    error "jproto expects an optional type name after the parameters list", ret

  # Build parameters list
  var params: seq[NimNode]
  for i in 1..<proto.len:
    let n = proto[i].strVal
    let coded = typeCode(n)
    if coded != "":
      params.add newLit(coded)
    else:
      params.add copyNimNode(proto[i])   # TODO: or can we just reuse proto[i] ?
  let paramsTree = newTree(nnkBracket, params)

  # Build return type
  var rett: NimNode = newLit("V")
  if ret.kind == nnkStmtList:
    let coded = ret[0].strVal.typeCode
    if coded != "":
      rett = newLit(coded)
    else:
      rett = copyNimNode(ret[0])

  # Build result
  let clazz = copyNimNode(proto[0][0])
  let name = if proto[0][1].kind == nnkIdent:
      newLit(proto[0][1].strVal)
    else:
      var buf = ""
      for it in proto[0][1].items:
        buf.add it.strVal
      newLit(buf)
  result = quote do:
    Method(
      class: `clazz`,
      name: `name`,
      prototype: Prototype(
        ret: `rett`,
        params: @ `paramsTree`))
  # echo "======"
  # echo result.repr

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
