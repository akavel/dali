{.experimental: "codeReordering".}
import unittest
import macros
import strutils

import dali
include dali/macros

macro dclass2native_string(header, body: untyped): untyped =
  newStrLitNode(newStmtList(dclass2native(header, body)).repr)

let jni_hello_code = dclass2native_string com.akavel.hello2.HelloActivity {.public.} of Activity:
    proc `<clinit>`() {.static, constructor, regs:2, ins:0, outs:1.} =
      # System.loadLibrary("hello-mello")
      const_string(0, "hello-mello")
      invoke_static(0, jproto System.loadLibrary(String))
      return_void()
    proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
      invoke_direct(0, jproto Activity.`<init>`())
      return_void()
    proc onCreate(_: Bundle) {.public, regs:4, ins:2, outs:2.} =
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
      return jenv.NewStringUTF(jenv, "Hello from Nim dclass :D")
    proc nopVoid() {.public, native.} =
      discard jenv.NewStringUTF(jenv, "nop")

test "jni_hello.so code as string":
  let wantCode = """
proc Java_com_akavel_hello2_HelloActivity_stringFromJNI*(jenv: JNIEnvPtr;
    jthis: jobject): jstring {.cdecl, exportc, dynlib.} =
  return jenv.NewStringUTF(jenv, "Hello from Nim dclass :D")

proc Java_com_akavel_hello2_HelloActivity_nopVoid*(jenv: JNIEnvPtr; jthis: jobject): void {.
    cdecl, exportc, dynlib.} =
  discard jenv.NewStringUTF(jenv, "nop")
"""
  check trim(wantCode) == trim(jni_hello_code)

proc trim(s: string): string =
  var x = s
  x.removePrefix
  x.removePrefix "["  # not sure why this shows up in NimNode.repr :/
  x.removePrefix
  x.removeSuffix {' '}
  x.removeSuffix
  x.removeSuffix "]"  # not sure why this shows up in NimNode.repr :/
  x.removeSuffix
  return "\n" & x.replace(" ", "·").replace("\t", "¬").replace("\n", "¶\n") & "\n"

