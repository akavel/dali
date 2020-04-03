{.experimental: "codeReordering".}
import algorithm
import std/macros
import options
import sequtils
import sets
import strutils

import dali/utils/macromatch

import dali/dex

macro jproto*(prototype: untyped): untyped =
  ## jproto is a macro converting a prototype declaration into a dali Method object.
  ## Example:
  ##
  ##   let HelloWorld = "Lcom/hello/HelloWorld;"
  ##   let String = "Ljava/lang/String;"
  ##   jproc HelloWorld.hello(String, int): String
  ##   jproc HelloWorld.`<init>`()
  ##   # NOTE: jproc argument must not be parenthesized; the following does not work unfortunately:
  ##   # jproc(HelloWorld.hello(String, int): String)
  ##
  ## TODO: support Java array types, i.e. int[], int[][], etc.
  # echo proto.treeRepr
  # echo ret.treeRepr
  # result = nnkStmtList.newTree()
  # echo "----------------"
  var proto = prototype

  # Parse & verify that proto has correct syntax
  # ...return type if present
  var rett = newLit("V")
  if proto =~ Infix(Ident("->"), [], Ident(_)):
    rett = proto[2].handleJavaType
    proto = proto[1]
  # ...class & method name:
  if proto !~ Call(_):
    error "jproto expects a method declaration as an argument", proto
  if proto !~ Call(DotExpr(_), _):
    error "jproto expects dot-separated class & method name in the argument", proto
  if proto[0] !~ DotExpr(Ident(_), Ident(_)) and
    proto[0] !~ DotExpr(Ident(_), AccQuoted(_)):
    error "jproto expects exactly 2 dot-separated names in the argument", proto[0]
  # ... parameters list:
  for i in 1..<proto.len:
    if proto[i] !~ Ident(_):
      error "jproto expects type names as method parameters", proto[i]

  # Build parameters list
  var params: seq[NimNode]
  for i in 1..<proto.len:
    params.add proto[i].handleJavaType
  let paramsTree = newTree(nnkBracket, params)

  # Build result
  let class = copyNimNode(proto[0][0])
  let name = proto[0][1].collectProcName
  result = quote do:
    Method(
      class: `class`,
      name: `name`,
      prototype: Prototype(
        ret: `rett`,
        params: @ `paramsTree`))
  # echo "======"
  # echo result.repr

proc collectProcName*(n: NimNode): NimNode =
  if n =~ Ident(_):
    newLit(n.strVal)
  else:
    var buf = ""
    for it in n.items:
      buf.add it.strVal
    newLit(buf)

proc typeLetter(fullType: string): string =
  ## typeLetter returns a one-letter code of a Java/Android primitive type,
  ## as represented in bytecode. Returns empty string if the input type is not known.
  case fullType
  of "jvoid","void": "V"
  of "jboolean","boolean": "Z"
  of "jbyte","byte": "B"
  of "jchar","char": "C"
  of "jint","int": "I"
  of "jlong","long": "J"
  of "jfloat","float": "F"
  of "jdouble","double": "D"
  of "jshort","short": "S"
  else: ""

proc handleJavaType(n: NimNode): NimNode =
  ## handleJavaType checks if n is an identifer corresponding to a Java type name.
  ## If yes, it returns a string literal with a one-letter code of this type. Otherwise,
  ## it returns a copy of the original node n.
  let coded = n.strVal.typeLetter
  if coded != "":
    return newLit(coded)
  case n.strVal
  of "jstring": return newLit("Ljava/lang/String;")
  of "jobject": return newLit("Ljava/lang/Object;")
  of "JClass": return newLit("Ljava/lang/Class;")
  of "jthrowable": return newLit("Ljava/lang/Throwable;")
  else:
    return copyNimNode(n)


macro dclass*(header, body: untyped): untyped =
  dclass2ClassDef(header, body)

# Goal sketch:
#
# let
#   HelloActivity = jtype com.akavel.hello2.HelloActivity
#   Activity = jtype android.app.Activity
#   Bundle = jtype android.os.Bundle
#   String = jtype java.lang.String
# dex "hellomello.dex":
#   dclass HelloActivity {.public.} of Activity:
#     # LATER: automatic loadLibrary in `<clinit>`
#     # LATER LATER: some syntax for constructor calling base class constructor
#     var x: int   # Nim int
#     proc onCreate(_: Bundle) {.dalvik, public, regs: 4, ...} =
#       invoke_super(2, 3, jproto Activity.onCreate(Bundle))
#       ...
#     proc sampleNative(y: jint): String
#       self.x = y
#       return jstring("x = {}" % self.x)

macro classes_dex*(filename: string, body: untyped): untyped =
  result = nnkStmtList.newTree()
  # echo body.treeRepr

  # Expecting a list of "dclass Foo {.public.} of Bar:" definitions
  if body !~ StmtList(_):
    error "classes_dex expects a list of 'dclass' definitions", body
  for c in body:
    if c !~ Command(Ident("dclass"), [], []):
      error "expected 'dclass' keyword", c

  when defined android:
    for c in body:
      result.add dclass2native(c[1], c[2])

  when not defined android:
    let dex = genSym()
    let newDex = bindSym"newDex"
    result.add(quote do:
      let `dex` = `newDex`())
    for c in body:
      let cl = dclass2ClassDef(c[1], c[2])
      result.add(quote do:
        `dex`.classes.add(`cl`))
    let renderDex = bindSym"renderDex"
    result.add(quote do:
      `renderDex`(`dex`, `filename`))

proc renderDex(dex: Dex, filename: string) =
  ## Temporary workaround for https://github.com/nim-lang/Nim/issues/12315
  ## (write & writeFile skip null bytes on Windows)
  let buf = dex.render
  var f: File
  if f.open(filename, fmWrite):
    try:
      f.writeBuffer(buf[0].unsafeAddr, buf.len)
    finally:
      close(f)
  else:
    raise newException(IOError, "cannot open: classes.dex")

proc dclass2native(header, body: NimNode): seq[NimNode] =
  var h = parseDClassHeader(header)
  for procDef in body:
    let p = parseDClassProc(procDef)
    if not p.native:
      continue
    let
      # TODO: handle '$' in class names
      nameAST = ident("Java_" & h.fullName.join("_") & "_" & p.name.strVal)
      bodyAST = p.body
      jenv = ident("jenv")
      jthis = ident("jthis")
      # Note: below procAST is not complete yet at this
      # phase, but it's a good starting point.
      procAST = quote do:
        proc `nameAST`*(`jenv`: JNIEnvPtr, `jthis`: jobject) {.cdecl,exportc,dynlib.} =
          `bodyAST`
    # Transplant the proc's returned type
    procAST.params[0] = p.ret
    # Append original proc's parameters to the procAST
    for param in p.params:
      procAST.params.add newIdentDefs(param.name, param.typ)
    result.add procAST

proc dclass2ClassDef(header, body: NimNode): NimNode =
  var h = parseDClassHeader(header)

  # Translate the class name to a string understood by Java bytecode. Do it
  # here as it'll be needed below.
  let classString = "L" & h.fullName.join("/") & ";"

  # Parse class body - a list of proc definitions
  if body !~ StmtList(_):
    error "expected a list of proc definitions", body
  var
    directMethods: seq[NimNode]
    virtualMethods: seq[NimNode]
  for procDef in body:
    let p = parseDClassProc(procDef)

    var instrs: seq[NimNode]
    if not p.native:
      # check proc body
      if p.body =~ Empty():
        continue
      if p.body !~ StmtList(_):
        error "unexpected syntax of proc body", p.body
      for stmt in p.body:
        case stmt.kind
        of nnkCall:
          instrs.add stmt
        of nnkCommand:
          var call = newTree(nnkCall)
          stmt.copyChildrenTo(call)
          call.copyLineInfo(stmt)
          instrs.add call
        of nnkIdent:
          instrs.add newCall(stmt)
        else:
          error "expected proc body to contain only Android assembly instructions", stmt

    # Rewrite the procedure as an EncodedMethod object
    let
      name = p.name.collectProcName
      paramsTree = newTree(nnkBracket, p.params[0..^1].mapIt(it.typ.handleJavaType))
      ret = p.ret.handleJavaType
      procAccessTree = newTree(nnkCurly, p.pragmas)
      regsTree = newLit(p.regs)
      insTree = newLit(p.ins)
      outsTree = newLit(p.outs)
      codeTree =
        if instrs.len > 0:
          let instrsTree = newTree(nnkBracket, instrs)
          quote do:
            Code(
              registers: `regsTree`,
              ins: `insTree`,
              outs: `outsTree`,
              instrs: @`instrsTree`)
        else:
          quote do:
            nil
    let enc = quote do:
      EncodedMethod(
        m: Method(
          class: `classString`,
          name: `name`,
          prototype: Prototype(
            ret: `ret`,
            params: @ `paramsTree`)),
        access: `procAccessTree`,
        code: `codeTree`)
    # echo enc.repr  # this prints Nim code - Thanks @disruptek on Nim chatroom for the hint!
    # echo enc.treeRepr
    if p.direct:
      directMethods.add enc
    else:
      virtualMethods.add enc

  let classTree = newLit(classString)

  # Add "nimSelf" field to the class if specified in pragmas.
  # TODO: add it always when there are any native methods?
  let instanceFieldsTree = newTree(nnkBracket)
  if h.hasNimSelf:
    instanceFieldsTree.add(quote do:
      EncodedField(
        f: Field(
          class: `classTree`,
          typ: "J",
          name: "nimSelf"),
        access: {Private}))

  # Render collected data into a ClassDef object
  let
    accessTree = newTree(nnkCurly, h.pragmas)
    super = h.super
    superclassTree =
      if super =~ Empty():
        quote do:
          none(Type)
      else:
        quote do:
          some(`super`)
    directMethodsTree = newTree(nnkBracket, directMethods)
    virtualMethodsTree = newTree(nnkBracket, virtualMethods)
  # TODO: also, create a `let` identifer for the class name
  result = quote do:
    ClassDef(
      class: `classTree`,
      access: `accessTree`,
      superclass: `superclassTree`,
      class_data: ClassData(
        instance_fields: @`instanceFieldsTree`,
        direct_methods: @`directMethodsTree`,
        virtual_methods: @`virtualMethodsTree`))



type DClassHeaderInfo = tuple
  super: NimNode         # nnkEmpty if no superclass declared
  pragmas: seq[NimNode]  # pragmas, with first letter modified to uppercase
  hasNimSelf: bool
  fullName: seq[string]  # Fully Qualified Class Name

proc parseDClassHeader(header: NimNode): DClassHeaderInfo =
  ## parseDClassHeader parses Java class header (class name & various modifiers)
  ## specified in Nim-like syntax.
  ## Example:
  ##
  ##     com.akavel.hello2.HelloActivity {.public.} of Activity
  ##
  ## corresponds to:
  ##
  ##     package com.akavel.hello2;
  ##     public class HelloActivity extends Activity { ... }

  # [com.foo.Bar {.public.}] of Activity
  result.super = newEmptyNode()
  var rest = header
  if header =~ Infix(Ident("of"), [], []):
    result.super = header[2]
    rest = header[1]

  # [com.foo.Bar] {.public.}
  if rest =~ PragmaExpr(_):
    if rest !~ PragmaExpr([], []):
      error "encountered unexpected syntax (too many words)", rest
    if rest !~ PragmaExpr([], Pragma(_)):
      error "expected pragmas list", rest[1]
    for p in rest[1]:
      if p !~ Ident(_):
        error "expected a simple pragma identifer", p
      let x = ident(p.strVal.capitalizeAscii)
      if x.strVal.eqIdent "NimSelf":
        result.hasNimSelf = true
        continue
      x.copyLineInfo(p)
      result.pragmas.add x
    rest = rest[0]

  # com.foo.[Bar]
  while rest =~ DotExpr(_):
    # TODO: allow and handle "$" character in class names
    if rest !~ DotExpr([], Ident(_)):
      error "expected 2+ dot-separated simple identifiers", rest
    result.fullName.add rest[1].strVal
    rest = rest[0]

  # [com.foo.]Bar
  if rest !~ Ident(_):
    error "expected dot-separated simple identifiers", rest
  result.fullname.add rest.strVal
  # After the processing above, fullName has unnatural, reversed order of segments; fix this
  reverse(result.fullname)

type DClassProcInfo = tuple
  name: NimNode
  pragmas: seq[NimNode]
  direct, native: bool
  regs, ins, outs: int
  params: seq[tuple[name, typ: NimNode]]
  ret: NimNode
  body: NimNode

proc parseDClassProc(procDef: NimNode): DClassProcInfo =
  if procDef !~ ProcDef(_):
    error "expected a proc definition", procDef
  # Parse proc header
  const
    # important indexes in nnkProcDef children,
    # see: https://nim-lang.org/docs/macros.html#statements-procedure-declaration
    i_name = 0

  # proc name must be a simple identifier, or backtick-quoted name
  if procDef[i_name] !~ Ident(_) and procDef[i_name] !~ AccQuoted(_):
    error "expected a proc name to be a simple identifier, or a backtick-quoted name", procDef[0]
  result.name = procDef[i_name]

  if procDef[1] !~ Empty():
    error "unexpected term rewriting pattern", procDef[1]
  if procDef[2] !~ Empty():
    error "unexpected generic type param", procDef[2]
  # TODO: shouldn't below also contain Final???
  const directMethodPragmas = toHashSet(["Static", "Private", "Constructor"])
  if procDef.pragma =~ Pragma(_):
    for p in procDef.pragma:
      if p =~ Ident(_):
        let x = ident(p.strVal.capitalizeAscii)
        x.copyLineInfo(p)
        result.pragmas.add x
        if x.strVal in directMethodPragmas:
          result.direct = true
        elif x.strVal == "Native":
          result.native = true
      elif p =~ ExprColonExpr(Ident(_), IntLit(_)):
        case p[0].strVal
        of "regs": result.regs = p[1].intVal.int
        of "ins":  result.ins = p[1].intVal.int
        of "outs": result.outs = p[1].intVal.int
        else: error "expected one of: 'regs: N', 'ins: N', 'outs: N' or access pragmas", p[0]
      else:
        error "unexpected format of pragma", p
  # proc return type
  result.ret = ident("void")  # 'void' by default
  if procDef.params[0] !~ Empty():
    result.ret = procDef.params[0]
  # check & collect proc params
  result.params = extractParams(procDef)
  # copy proc body
  result.body = procDef.body

proc extractParams(procDef: NimNode): seq[tuple[name, typ: NimNode]] =
  for p in procDef.params[1..^1]:
    if p[^2] =~ Empty(): error "missing type for param", p
    if p[^1] !~ Empty(): error "default param values not supported", p[^1]
    for name in p[0..^3]:
      result.add (name, p[^2])

