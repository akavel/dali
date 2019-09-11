import unittest
import macros
import algorithm
import strutils
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


macro jclass(header: untyped): untyped =
  ## TODO
  result = nnkStmtList.newTree()
  echo header.treeRepr
  echo "----------"

macro jclass(header, body: untyped): untyped =
  result = nnkStmtList.newTree()
  echo header.treeRepr
  echo body.treeRepr
  echo "----------"

  # Parse header
  var super = ident("Ljava/lang/Object;")  # by default, classes inherit from Object
  var rest = header
  # [jclass com.foo.Bar {.public.}] of Activity
  if header.kind == nnkInfix and
    header[0].kind == nnkIdent and
    header[0].strVal == "of":
    super = header[2]  # TODO: copyNimNode ?
    rest = header[1]
  # [jclass com.foo.Bar] {.public.}
  var pragmas: seq[string]
  if rest.kind == nnkPragmaExpr:
    if rest.len != 2:
      error "jclass encountered unexpected syntax (too many words)", rest
    if rest[1].kind != nnkPragma:
      error "jclass expected pragmas list", rest[1]
    for p in rest[1]:
      if p.kind != nnkIdent:
        error "jclass expects a simple pragma identifer", p
      pragmas.add p.strVal
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

  # Parse body - a list of proc definitions
  if body.kind != nnkStmtList:
    error "jclass expects a list of proc definitions", body
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
    var pragmas: seq[NimNode]
    if procDef[i_pragmas].kind == nnkPragma:
      for p in procDef[i_pragmas]:
        pragmas.add ident(p.strVal.capitalizeAscii)
    # proc return type
    #...
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

  # error "TODO... NIY"

jclass hw {.public.}

jclass com.foo.Bar  # no pragmas

jclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
  proc `<init>`() {.public, final, constructor.} =
    invoke_direct(0, jproto Application.`<init>`())
    return_void()

jclass com.android.hello.HelloAndroid {.public.} of Activity:
  proc `<init>`() {.public, final, constructor.} =
    invoke_direct(0, jproto Activity.`<init>`())
    return_void()
  proc fooBar(Bundle, View, int)
  proc onCreate(Bundle) {.public.} =
    invoke_super(1, 2, jproto Activity.onCreate(Bundle))
    const_high16(0, 0x7f03)
    invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
    return_void()

