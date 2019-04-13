{.experimental: "codeReordering".}
import src / dali

# Based on: https://github.com/czak/minimal-android-project/blob/9aad6bd2f1f443aa8dfe887d3ed6ea27576aa609/src/main/java/pl/czak/minimal/MainActivity.java

const
  Activity = "Landroid/app/Activity;"
  HelloActivity = "Lcom/akavel/hello/HelloActivity;"
  Bundle = "Landroid/os/Bundle;"
  TextView = "Landroid/widget/TextView;"

var dex = newDex()
dex.classes.add(ClassDef(
  class: HelloActivity,
  access: {Public},
  superclass: SomeType(Activity),
  class_data: ClassData(
    direct_methods: @[
      EncodedMethod(
        m: Method(
          class: HelloActivity,
          name: "<init>",
          prototype: Prototype(ret: "V", params: @[]),
        ),
        access: {Public, Constructor},
        code: SomeCode(Code(
          registers: 1,
          ins: 1,
          outs: 1,
          instrs: @[
            invoke_direct(0, Method(class: Activity, name: "<init>",
              prototype: Prototype(ret: "V", params: @[]))),
            return_void(),
          ],
        )),
      ),
    ],
    virtual_methods: @[
      EncodedMethod(
        m: Method(
          class: HelloActivity,
          name: "onCreate",
          prototype: Prototype(ret: "V", params: @[Bundle])),
        access: {Public},
        code: SomeCode(Code(
          registers: 4,
          ins: 2,
          outs: 2,  # TODO(akavel): what does this really mean???
          instrs: @[
            invoke_super(2, 3, Method(class: Activity, name: "onCreate",
              prototype: Prototype(ret: "V", params: @[Bundle]))),
            new_instance(0, TextView),
            invoke_direct(0, 2, Method(class: TextView, name: "<init>",
              prototype: Prototype(ret: "V", params: @["Landroid/content/Context;"]))),
            const_string(1, "Hello dali!"),
            invoke_virtual(0, 1, Method(class: TextView, name: "setText",
              prototype: Prototype(ret: "V", params: @["Ljava/lang/CharSequence;"]))),
            invoke_virtual(2, 0, Method(class: HelloActivity, name: "setContentView",
              prototype: Prototype(ret: "V", params: @["Landroid/view/View;"]))),
            return_void(),
          ],
        )),
      ),
    ]
  )
))
stdout.write(dex.render)

