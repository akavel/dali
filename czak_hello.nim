{.experimental: "codeReordering".}
import src / dali

# Based on: https://github.com/czak/minimal-android-project/blob/9aad6bd2f1f443aa8dfe887d3ed6ea27576aa609/src/main/java/pl/czak/minimal/MainActivity.java

const
  Activity = "Landroid/app/Activity;"
  HelloActivity = "Lcom/akavel/hello/HelloActivity;"
  Bundle = "Landroid/os/Bundle;"
  TextView = "Landroid/widget/TextView;"
  Context = "Landroid/content/Context;"
  CharSequence = "Ljava/lang/CharSequence;"
  View = "Landroid/view/View;"

var dex = newDex()
dex.classes.add:
  dclass com.akavel.hello.HelloActivity {.public.} of Activity:
    proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
      invoke_direct(0, jproto Activity.`<init>`())
      return_void()
    proc onCreate(Bundle) {.public, regs:4, ins:2, outs:2.} =
      invoke_super(2, 3, jproto Activity.onCreate(Bundle))
      new_instance(0, TextView)
      invoke_direct(0, 2, jproto TextView.`<init>`(Context))
      const_string(1, "Hello dali!")
      invoke_virtual(0, 1, jproto TextView.setText(CharSequence))
      invoke_virtual(2, 0, jproto HelloActivity.setContentView(View))
      return_void()

stdout.write(dex.render)

