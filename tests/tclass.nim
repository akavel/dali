import unittest
import macros
import algorithm
import strutils
import sets
import dali

let
  Object = "Ljava/lang/Object;"
  Application = "Landroid/app/Application;"
  Activity = "Landroid/app/Activity;"


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


let
  # TODO: shouldn't below also contain Final???
  directMethodPragmas = toSet(["Static", "Private", "Constructor"])

macro jclass(header: untyped): untyped =
  ## TODO
  result = nnkStmtList.newTree()
  echo header.treeRepr
  echo "----------"

macro jclass(header, body: untyped): untyped =
  result = nnkStmtList.newTree()
  # echo header.treeRepr
  # echo body.treeRepr
  echo "----------"

  # Parse class header (class name & various modifiers)
  var super = newEmptyNode()
  var rest = header
  # [jclass com.foo.Bar {.public.}] of Activity
  if header.kind == nnkInfix and
    header[0].kind == nnkIdent and
    header[0].strVal == "of":
    super = header[2]  # TODO: copyNimNode ?
    rest = header[1]
  # [jclass com.foo.Bar] {.public.}
  var pragmas: seq[NimNode]
  if rest.kind == nnkPragmaExpr:
    if rest.len != 2:
      error "jclass encountered unexpected syntax (too many words)", rest
    if rest[1].kind != nnkPragma:
      error "jclass expected pragmas list", rest[1]
    for p in rest[1]:
      if p.kind != nnkIdent:
        error "jclass expects a simple pragma identifer", p
      pragmas.add ident(p.strVal.capitalizeAscii)
    rest = rest[0]
  # [jclass] com.foo.[Bar]
  var classPath: seq[string]
  while rest.kind == nnkDotExpr:
    if rest.len != 2:
      error "jclass expects 2 elements separated by dot", rest
    # TODO: allow and handle "$" character in class names
    if rest[1].kind != nnkIdent:
      error "jclass expects dot-separated simple identifiers", rest[1]
    classPath.add rest[1].strVal
    rest = rest[0]
  # [jclass com.foo.]Bar
  if rest.kind != nnkIdent:
    error "jclass expects dot-separated simple identifiers", rest
  classPath.add rest.strVal
  # After the processing above, classPath has unnatural, reversed order of segments; fix this
  reverse(classPath)
  # echo classPath.repr

  # Translate the class name to a string understood by Java bytecode. Do it
  # here as it'll be needed below.
  let classString = "L" & classPath.join(".") & ";"

  # Parse class body - a list of proc definitions
  if body.kind != nnkStmtList:
    error "jclass expects a list of proc definitions", body
  var
    directMethods: seq[NimNode]
    virtualMethods: seq[NimNode]
  for procDef in body:
    if procDef.kind != nnkProcDef:
      error "jclass expects a list of proc definitions", procDef
    # Parse proc header
    const
      # important indexes in nnkProcDef children,
      # see: https://nim-lang.org/docs/macros.html#statements-procedure-declaration
      i_name = 0
      i_params = 3
      i_pragmas = 4
      i_body = 6
    # proc name must be a simple identifier, or backtick-quoted name
    if procDef[i_name].kind notin {nnkIdent, nnkAccQuoted}:
      error "jclass expects a proc name to be a simple identifier, or a backtick-quoted name", procDef[0]
    if procDef[1].kind != nnkEmpty: error "unexpected term rewriting pattern in jclass proc", procDef[1]
    if procDef[2].kind != nnkEmpty: error "unexpected generic type param in jclass proc", procDef[2]
    # proc pragmas
    var
      procPragmas: seq[NimNode]
      isDirect = false
      procRegs = 0
      procIns = 0
      procOuts = 0
    if procDef[i_pragmas].kind == nnkPragma:
      for p in procDef[i_pragmas]:
        if p.kind notin {nnkIdent, nnkExprColonExpr}:
          error "unexpected format of pragma in jclass proc", p
        if p.kind == nnkIdent:
          let capitalized = p.strVal.capitalizeAscii
          procPragmas.add ident(capitalized)
          if capitalized in directMethodPragmas:
            isDirect = true
        else:
          if p[0].kind != nnkIdent: error "unexpected format of pragma in jclass proc", p[0]
          if p[1].kind != nnkIntLit: error "unexpected format of pragma in jclass proc", p[1]
          case p[0].strVal
          of "regs": procRegs = p[1].intVal.int
          of "ins":  procIns = p[1].intVal.int
          of "outs": procOuts = p[1].intVal.int
          else: error "expected one of: 'regs: N', 'ins: N', 'outs: N' or access pragmas", p[0]
    # proc return type
    var ret: NimNode = newLit("V")
    if procDef[i_params][0].kind != nnkEmpty:
      ret = procDef[i_params][0].handleJavaType
    # check & collect proc params
    var params: seq[NimNode]
    if procDef[i_params].len > 2: error "unexpected syntax of proc params (must be a list of type names)", procDef[i_params]
    if procDef[i_params].len == 2:
      let
        rawParams = procDef[i_params][1]
        n = rawParams.len
      if rawParams[n-1].kind != nnkEmpty: error "unexpected syntax of proc param (must be a name of a type)", rawParams[n-1]
      if rawParams[n-2].kind != nnkEmpty: error "unexpected syntax of proc param (must be a name of a type)", rawParams[n-2]
      for i in 0..<rawParams.len-2:
        params.add rawParams[i].handleJavaType
    # check proc body
    var pbody: seq[NimNode]
    if procDef[i_body].kind notin {nnkEmpty, nnkStmtList}:
      error "unexpected syntax of jclass proc body", procDef[i_body]
    if procDef[i_body].kind == nnkStmtList:
      for stmt in procDef[i_body]:
        if stmt.kind != nnkCall:
          error "jclass expects proc body to contain only Android assembly instructions", stmt
        pbody.add stmt

    # Rewrite the procedure as an EncodedMethod object
    let
      name = procDef[i_name].collectProcName
      paramsTree = newTree(nnkBracket, params)
      procAccessTree = newTree(nnkCurly, procPragmas)
      regsTree = newLit(procRegs)
      insTree = newLit(procIns)
      outsTree = newLit(procOuts)
      codeTree =
        if pbody.len > 0:
          let instrs = newTree(nnkBracket, pbody)
          quote do:
            SomeCode(Code(
              registers: `regsTree`,
              ins: `insTree`,
              outs: `outsTree`,
              instrs: @`instrs`))
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
    if isDirect:
      directMethods.add enc
    else:
      virtualMethods.add enc

  # Render collected data into a ClassDef object
  let
    classTree = newLit(classString)
    accessTree = newTree(nnkCurly, pragmas)
    superclassTree =
      if super.kind == nnkEmpty:
        quote do:
          NoType()
      else:
        quote do:
          SomeType(`super`)
    directMethodsTree = newTree(nnkBracket, directMethods)
    virtualMethodsTree = newTree(nnkBracket, virtualMethods)
  let classDef = quote do:
    ClassDef(
      class: `classTree`,
      access: `accessTree`,
      superclass: `superclassTree`,
      class_data: ClassData(
        direct_methods: @`directMethodsTree`,
        virtual_methods: @`virtualMethodsTree`))
  echo classDef.repr

  # error "TODO... NIY"

# dumpTree SomeCode(Code(registers: 3))
# dumpTree:
#   proc foo() {.public, bar: 1, baz: 2.} =
#     discard

jclass hw {.public.}

jclass com.foo.Bar  # no pragmas

jclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct(0, jproto Application.`<init>`())
    return_void()

jclass com.android.hello.HelloAndroid {.public.} of Activity:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct(0, jproto Activity.`<init>`())
    return_void()
  proc fooBar(Bundle, View, int)
  proc onCreate(Bundle) {.public, regs:3, ins:2, outs:2.} =
    invoke_super(1, 2, jproto Activity.onCreate(Bundle))
    const_high16(0, 0x7f03)
    invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
    return_void()

