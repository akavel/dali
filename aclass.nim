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
  var
    classes: seq[NimNode]
    nativeProcs: seq[NimNode]
  for c in body:
    if c !~ Command(Ident("aclass"), [], []):
      error "classes_dex expects a list of 'aclass' definitions", c[0]
    let (class, natProcs) = handleAclass(c[1], c[2])
    classes.add class
    nativeProcs.add natProcs

  let
    dex = genSym()
    newDex = bindSym"newDex"
    stdout = bindSym"stdout"
    write = bindSym"write"
    render = bindSym"render"
    nativeProcsTree = newTree(nnkStmtList, nativeProcs)
    classesTree = block:
      var tree = newTree(nnkStmtList)
      for c in classes:
        tree.add (quote do:
          `dex`.classes.add(`c`))
      tree
  result = quote do:
    when not defined android:
      let `dex` = `newDex`()
      `classesTree`
      `stdout`.`write`(`dex`.`render`)
    else:
      `nativeProcsTree`

proc handleAclass(header, body: NimNode): tuple[class: NimNode, natProcs: seq[NimNode]] =
  # echo header.treeRepr
  # echo body.treeRepr
  # echo "----------"

  # Parse class header (class name & various modifiers)
  var
    headerInfo = parseJClassHeader(header)
    super = headerInfo.super
    pragmas = headerInfo.pragmas
    classPath = headerInfo.fullName
  # echo classPath.repr

  # Translate the class name to a string understood by Java bytecode. Do it
  # here as it'll be needed below.
  let classString = "L" & classPath.join("/") & ";"

  # Parse class body - a list of proc definitions
  if body !~ StmtList(_):
    error "aclass expects a list of proc definitions", body
  var
    directMethods: seq[NimNode]
    virtualMethods: seq[NimNode]
    nativeMethods: seq[NimNode]
  for procDef in body:
    if procDef !~ ProcDef(_):
      error "aclass expects a list of proc definitions", procDef
    # Parse proc header
    const
      # important indexes in nnkProcDef children,
      # see: https://nim-lang.org/docs/macros.html#statements-procedure-declaration
      i_name = 0
      i_params = 3
      i_pragmas = 4
      i_body = 6
    # proc name must be a simple identifier, or backtick-quoted name
    if procDef[i_name] !~ Ident(_) and
      procDef[i_name] !~ AccQuoted(_):
      error "aclass expects a proc name to be a simple identifier, or a backtick-quoted name", procDef[0]
    if procDef[1] !~ Empty(): error "unexpected term rewriting pattern in aclass proc", procDef[1]
    if procDef[2] !~ Empty(): error "unexpected generic type param in aclass proc", procDef[2]
    # proc pragmas
    var
      procPragmas: seq[NimNode]
      isDirect = false
      isNative = false
      procRegs = 0
      procIns = 0
      procOuts = 0
    let
      # TODO: shouldn't below also contain Final???
      directMethodPragmas = toSet(["Static", "Private", "Constructor"])
    if procDef[i_pragmas] =~ Pragma(_):
      for p in procDef[i_pragmas]:
        if p =~ Ident(_):
          let capitalized = p.strVal.capitalizeAscii
          procPragmas.add ident(capitalized)
          if capitalized in directMethodPragmas:
            isDirect = true
          elif capitalized == "Native":
            isNative = true
        elif p =~ ExprColonExpr(Ident(_), IntLit(_)):
          case p[0].strVal
          of "regs": procRegs = p[1].intVal.int
          of "ins":  procIns = p[1].intVal.int
          of "outs": procOuts = p[1].intVal.int
          else: error "expected one of: 'regs: N', 'ins: N', 'outs: N' or access pragmas", p[0]
        else:
          error "unexpected format of pragma in aclass proc", p
    # proc return type
    var ret: NimNode = newLit("V")
    if procDef[i_params][0] !~ Empty():
      ret = procDef[i_params][0].handleJavaType
    # check & collect proc params
    var params: seq[NimNode]
    if procDef[i_params].len > 2: error "unexpected syntax of proc params (must be a list of type names)", procDef[i_params]
    if procDef[i_params].len == 2:
      let rawParams = procDef[i_params][1]
      if rawParams[^1] !~ Empty(): error "unexpected syntax of proc param (must be a name of a type)", rawParams[^1]
      if rawParams[^2] !~ Empty(): error "unexpected syntax of proc param (must be a name of a type)", rawParams[^2]
      for p in rawParams[0..^3]:
        params.add p.handleJavaType
    # check proc body
    var pbody: seq[NimNode]
    if procDef[i_body] =~ StmtList(_):
      if isNative:
        nativeMethods.add handleNativeMethod(classPath, procDef)
      else:
        for stmt in procDef[i_body]:
          case stmt.kind
          of nnkCall:
            pbody.add stmt
          of nnkCommand:
            var call = newTree(nnkCall)
            stmt.copyChildrenTo(call)
            call.copyLineInfo(stmt)
            pbody.add call
          of nnkIdent:
            pbody.add newCall(stmt)
          else:
            error "aclass expects proc body to contain only Android assembly instructions", stmt
    elif procDef[i_body] =~ Empty():
      discard
    else:
      error "unexpected syntax of aclass proc body", procDef[i_body]
    # echo nativeMethods.repr

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
      if super =~ Empty():
        quote do:
          NoType()
      else:
        quote do:
          SomeType(`super`)
    directMethodsTree = newTree(nnkBracket, directMethods)
    virtualMethodsTree = newTree(nnkBracket, virtualMethods)
  # TODO: also, create a `let` identifer for the class name
  let classDef = quote do:
    ClassDef(
      class: `classTree`,
      access: `accessTree`,
      superclass: `superclassTree`,
      class_data: ClassData(
        direct_methods: @`directMethodsTree`,
        virtual_methods: @`virtualMethodsTree`))
  # echo classDef.repr

  result = (
    class: classDef,
    natProcs: nativeMethods)

type AClassHeaderInfo = tuple
  super: NimNode         # nnkEmpty if no superclass declared
  pragmas: seq[NimNode]  # pragmas, with first letter modified to uppercase
  fullName: seq[string]  # Fully Qualified Class Name

proc parseJClassHeader(header: NimNode): AClassHeaderInfo =
  ## parseJClassHeader parses Java class header (class name & various modifiers)
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

proc handleNativeMethod(classPath: seq[string], procDef: NimNode): NimNode =
  const
    # important indexes in nnkProcDef children,
    # see: https://nim-lang.org/docs/macros.html#statements-procedure-declaration
    i_name = 0
    i_params = 3
    i_body = 6
  # TODO: handle '$' in class names
  let
    procName = ident("Java_" & classPath.join("_") & "_" & procDef[i_name].strVal)
    bodyTree = procDef[i_body]
    # Below procTree is not complete yet, but it's a good starting point.
    procTree = quote do:
      proc `procName`*(jenv: JNIEnvPtr, jthis: jobject) {.cdecl,exportc,dynlib.} =
        `bodyTree`
  # Remove `gensym tag from parameters
  procTree[i_params][1][0] = ident("jenv")
  procTree[i_params][2][0] = ident("jthis")
  # Transplant the proc's returned type
  procTree[i_params][0] = procDef[i_params][0]
  # Append original proc's parameters to the procTree
  for i in 1..<procDef[i_params].len:
    procTree[i_params].add procDef[i_params][i]
  return procTree

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
