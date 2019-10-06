{.experimental: "codeReordering".}
import macros
import strutils
import algorithm
import sets
import src/dali
import src/dali/utils/macromatch
import jni_wrapper

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
    dclass com.akavel.hello2.HelloActivity {.public.} of Activity:
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
        return jenv.NewStringUTF(jenv, "Hello from Nim dclass :D")

# dumpTree:
#   if foo =~ Ident([]):
#     while bar =~ Biz(_):
#       discard
