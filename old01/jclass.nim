
## Code more or less I'd like to be able to eventually run as macro to generate classes.dex:
#
# jtype
#   android.app.Activity
#   com.akavel.hello2.HelloActivity
#   android.os.Bundle
#   android.widget.TextView
#   java.lang.System
#   java.lang.String
#
# jclass HelloActivity {.public, extends: Activity.}:
#   `<clinit>`() {.final, static, constructor.} =
#     # System.loadLibrary("hello-mello")
#     const_string(v0, "hello-mello")
#     invoke_static(v0, System.loadLibrary(String))
#     #return_void()
#   `<init>`() {.final, public, constructor.} =
#     invoke_direct(v0, Activity.`<init>`())
#     #return_void()
#   onCreate(Bundle) {.public.} =
#     # super.onCreate(arg0) [this?]
#     invoke_super(v2, v3, Activity.onCreate(Bundle))
#     # v0 = new TextView(this)
#     new_instance(v0, TextView)
#     invoke_direct(v0, v2, TextView.`<init>`(jtype android.context.Context))
#     # v1 = this.stringFromJNI()
#     invoke_virtual(v2, HelloActivity.stringFromJNI(): String)
#     move_result_object(v1)
#     # v0.setText(v1)
#     invoke_virtual(v0, v1, TextView.setText(jtype java.lang.CharSequence))
#     # this.setContentView(v0)
#     invoke_virtual(v2, v0, HelloActivity.setContentView(jtype android.view.View))
#     #return_void()
#   stringFromJNI(): String {.public, native.}

# type JType = distinct string

# func jtype(humanReadable: string): JType =
#   case humanReadable
#   else:
#     return JType("L" & humanReadable.replace('.', '/') & ";")

#TODO:
# static:
#   writeFile(...)
