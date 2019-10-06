{.experimental: "codeReordering".}
import macros
import strutils
import algorithm
import sets

import dali/utils/macromatch

import dali/[types, dex, instrs]
export types, dex, instrs

proc typeLetter(fullType: string): string =
  ## typeLetter returns a one-letter code of a Java/Android primitive type,
  ## as represented in bytecode. Returns empty string if the input type is not known.
  case fullType
  of "void": "V"
  of "boolean": "Z"
  of "byte": "B"
  of "char": "C"
  of "int": "I"
  of "long": "J"
  of "float": "F"
  of "double": "D"
  else: ""

proc handleJavaType(n: NimNode): NimNode =
  ## handleJavaType checks if n is an identifer corresponding to a Java type name.
  ## If yes, it returns a string literal with a one-letter code of this type. Otherwise,
  ## it returns a copy of the original node n.
  let coded = n.strVal.typeLetter
  if coded != "":
    result = newLit(coded)
  else:
    result = copyNimNode(n)

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

macro dclass*(header, body: untyped): untyped =
  dclass2ClassDef(header, body)

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
      paramsTree = newTree(nnkBracket, p.params)
      ret = p.ret
      procAccessTree = newTree(nnkCurly, p.pragmas)
      regsTree = newLit(p.regs)
      insTree = newLit(p.ins)
      outsTree = newLit(p.outs)
      codeTree =
        if instrs.len > 0:
          let instrsTree = newTree(nnkBracket, instrs)
          quote do:
            SomeCode(Code(
              registers: `regsTree`,
              ins: `insTree`,
              outs: `outsTree`,
              instrs: @`instrsTree`))
        else:
          quote do:
            NoCode()
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

  # Render collected data into a ClassDef object
  let
    classTree = newLit(classString)
    accessTree = newTree(nnkCurly, h.pragmas)
    super = h.super
    superclassTree =
      if super =~ Empty():
        quote do:
          NoType()
      else:
        quote do:
          SomeType(`super`)
    directMethodsTree = newTree(nnkBracket, directMethods)
    virtualMethodsTree = newTree(nnkBracket, virtualMethods)
  # TODO: also, create a `let` identifer for the class name
  result = quote do:
    ClassDef(
      class: `classTree`,
      access: `accessTree`,
      superclass: `superclassTree`,
      class_data: ClassData(
        direct_methods: @`directMethodsTree`,
        virtual_methods: @`virtualMethodsTree`))



type DClassHeaderInfo = tuple
  super: NimNode         # nnkEmpty if no superclass declared
  pragmas: seq[NimNode]  # pragmas, with first letter modified to uppercase
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
  params: seq[NimNode]
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
    i_params = 3
    i_pragmas = 4
    i_body = 6

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
  if procDef[i_pragmas] =~ Pragma(_):
    for p in procDef[i_pragmas]:
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
  result.ret = newLit("V")  # 'void' by default
  if procDef[i_params][0] !~ Empty():
    result.ret = procDef[i_params][0].handleJavaType
  # check & collect proc params
  if procDef[i_params].len > 2: error "unexpected syntax of proc params (must be a list of type names)", procDef[i_params]
  if procDef[i_params].len == 2:
    let rawParams = procDef[i_params][1]
    if rawParams[^1] !~ Empty(): error "unexpected syntax of proc param (must be a name of a type)", rawParams[^1]
    if rawParams[^2] !~ Empty(): error "unexpected syntax of proc param (must be a name of a type)", rawParams[^2]
    for p in rawParams[0..^3]:
      result.params.add p.handleJavaType
  # copy proc body
  result.body = procDef[i_body]

