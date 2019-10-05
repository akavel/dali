{.experimental: "codeReordering".}
import macros
import strutils
import algorithm
import sets
import src / dali
import src / dali / macromatch
import jni_wrapper

# Goal sketch:
#
# let
#   HelloActivity = jtype com.akavel.hello2.HelloActivity
#   Activity = jtype android.app.Activity
#   Bundle = jtype android.os.Bundle
#   String = jtype java.lang.String
# dex "hellomello.dex":
#   aclass HelloActivity {.public.} of Activity:
#     # LATER: automatic loadLibrary in `<clinit>`
#     # LATER LATER: some syntax for constructor calling base class constructor
#     var x: int   # Nim int
#     proc onCreate(_: Bundle) {.dalvik, public, regs: 4, ...} =
#       invoke_super(2, 3, jproto Activity.onCreate(Bundle))
#       ...
#     proc sampleNative(y: jint): String
#       self.x = y
#       return jstring("x = {}" % self.x)


macro classes_dex*(body: untyped): untyped =
  result = nnkStmtList.newTree()
  # echo body.treeRepr

  # Expecting a list of "aclass Foo {.public.} of Bar:" definitions
  if body !~ StmtList(_):
    error "classes_dex expects a list of 'aclass' definitions", body
  for c in body:
    if c !~ Command(Ident("aclass"), [], []):
      error "expected 'aclass' keyword", c

  when defined android:
    for c in body:
      result.add aclass2native(c[1], c[2])

  when not defined android:
    let dex = genSym()
    let newDex = bindSym"newDex"
    result.add(quote do:
      let `dex` = `newDex`())
    for c in body:
      let cl = aclass2Class(c[1], c[2])
      result.add(quote do:
        `dex`.classes.add(`cl`))
    # let stdout = bindSym"stdout"
    let writeFile = bindSym"writeFile"
    let render = bindSym"render"
    result.add(quote do:
      `writeFile`("classes.dex", `dex`.`render`))
      # `stdout`.`write`(`dex`.`render`))

proc aclass2native(header, body: NimNode): seq[NimNode] =
  var h = parseAClassHeader(header)
  for procDef in body:
    let p = parseAClassProc(procDef)
    if not p.native:
      continue
    let
      # TODO: handle '$' in class names
      nameAST = ident("Java_" & h.fullName.join("_") & "_" & p.name.strVal)
      bodyAST = p.body
      # Note: below procAST is not complete yet at this
      # phase, but it's a good starting point.
      procAST = quote do:
        proc `nameAST`*(jenv: JNIEnvPtr, jthis: jobject) {.cdecl,exportc,dynlib.} =
          `bodyAST`
    # Remove `gensym tag from parameters
    procAST.params[1][0] = ident("jenv")
    procAST.params[2][0] = ident("jthis")
    # Transplant the proc's returned type
    procAST.params[0] = p.ret
    # Append original proc's parameters to the procAST
    for param in p.params:
      procAST.params.add param
    result.add procAST

proc aclass2Class(header, body: NimNode): NimNode =
  var h = parseAClassHeader(header)

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
    let p = parseAClassProc(procDef)

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



type AClassHeaderInfo = tuple
  super: NimNode         # nnkEmpty if no superclass declared
  pragmas: seq[NimNode]  # pragmas, with first letter modified to uppercase
  fullName: seq[string]  # Fully Qualified Class Name

proc parseAClassHeader(header: NimNode): AClassHeaderInfo =
  ## parseAClassHeader parses Java class header (class name & various modifiers)
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

type AClassProcInfo = tuple
  name: NimNode
  pragmas: seq[NimNode]
  direct, native: bool
  regs, ins, outs: int
  params: seq[NimNode]
  ret: NimNode
  body: NimNode

proc parseAClassProc(procDef: NimNode): AClassProcInfo =
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

proc typeLetter(fullType: string): string =
  ## typeLetter returns a one-letter code of a Java/Android primitive type,
  ## as represented in bytecode. Returns empty string if the input type is not known.
  case fullType
  of "void": "V"
  of "jboolean": "Z"
  of "jbyte": "B"
  of "jchar": "C"
  of "jint": "I"
  of "jlong": "J"
  of "jfloat": "F"
  of "jdouble": "D"
  of "jshort": "S"
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

# let
#   HelloActivity = jtype com.akavel.hello2.HelloActivity
#   Activity = jtype android.app.Activity
#   Bundle = jtype android.os.Bundle
#   String = jtype java.lang.String
let
  Activity = "Landroid/app/Activity;"
  HelloActivity = "Lcom/akavel/hello2/HelloActivity;"
  Bundle = "Landroid/os/Bundle;"
  TextView = "Landroid/widget/TextView;"
  System = "Ljava/lang/System;"
  String = "Ljava/lang/String;"
  Context = "Landroid/content/Context;"
  View = "Landroid/view/View;"
  CharSequence = "Ljava/lang/CharSequence;"

expandMacros:
  classes_dex:
    aclass com.akavel.hello2.HelloActivity {.public.} of Activity:
      proc `<clinit>`() {.static, constructor, regs:2, ins:0, outs:1.} =
        # System.loadLibrary("hello-mello")
        const_string(0, "hello-mello")
        invoke_static(0, jproto System.loadLibrary(String))
        return_void()
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Activity.`<init>`())
        return_void()
      proc onCreate(Bundle) {.public, regs:4, ins:2, outs:2.} =
        # ins: this, arg0
        # super.onCreate(arg0)
        invoke_super(2, 3, jproto Activity.onCreate(Bundle))
        # v0 = new TextView(this)
        new_instance(0, TextView)
        invoke_direct(0, 2, jproto TextView.`<init>`(Context))
        # v1 = this.stringFromJNI()
        #  NOTE: failure to call a Native function should result in
        #  java.lang.UnsatisfiedLinkError exception
        invoke_virtual(2, jproto HelloActivity.stringFromJNI() -> String)
        move_result_object(1)
        # v0.setText(v1)
        invoke_virtual(0, 1, jproto TextView.setText(CharSequence))
        # this.setContentView(v0)
        invoke_virtual(2, 0, jproto HelloActivity.setContentView(View))
        # return
        return_void()
      proc stringFromJNI(): jstring {.public, native.} =
        return jenv.NewStringUTF(jenv, "Hello from Nim aclass :D")

# dumpTree:
#   if foo =~ Ident([]):
#     while bar =~ Biz(_):
#       discard
