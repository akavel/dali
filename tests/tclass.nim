import unittest
import macros
import dali

let
  Object = "Ljava/lang/Object;"
  Application = "Landroid/app/Application;"
  Activity = "Landroid/app/Activity;"
  Bundle = "Landroid/os/Bundle;"
  View = "Landroid/view/View;"
  HelloAndroid = "Lcom/android/hello/HelloAndroid;"

# macro jclass(header: untyped): untyped =
#   ## TODO
#   result = nnkStmtList.newTree()
#   echo header.treeRepr
#   echo "----------"

# dumpTree SomeCode(Code(registers: 3))
# dumpTree:
#   proc foo() {.public, bar: 1, baz: 2.} =
#     discard

# discard jclass hw {.public.}

# discard jclass com.foo.Bar  # no pragmas

discard jclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct 0, jproto Application.`<init>`()
    return_void

discard jclass com.android.hello.HelloAndroid {.public.} of Activity:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct(0, jproto Activity.`<init>`())
    return_void()
  proc fooBar(Bundle, View, int)
  proc onCreate(Bundle) {.public, regs:3, ins:2, outs:2.} =
    invoke_super(1, 2, jproto Activity.onCreate(Bundle))
    const_high16(0, 0x7f03)
    invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
    return_void()

# TODO: test "hello_world.apk":

test "bugsnag.apk":
  let c =
    jclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Application.`<init>`())
        return_void()
  checkpoint c.repr
  check c.equals ClassDef(
    class: "Lcom/bugsnag/dexexample/BugsnagApp;",
    access: {Public}, # TODO
    superclass: SomeType("Landroid/app/Application;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/bugsnag/dexexample/BugsnagApp;",
            name: "<init>",
            prototype: Prototype(
              ret: "V",
              params: @[],
            ),
          ),
          access: {Public, Constructor},
          code: SomeCode(Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Application;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          )),
        )
      ]
    )
  )

test "hello_android.apk":
  let c =
    jclass com.android.hello.HelloAndroid {.public.} of Activity:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Activity.`<init>`())
        return_void()
      proc onCreate(Bundle) {.public, regs:3, ins:2, outs:2.} =
        invoke_super(1, 2, jproto Activity.onCreate(Bundle))
        const_high16(0, 0x7f03)
        invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
        return_void()
  checkpoint c.repr
  check c.equals ClassDef(
    class: "Lcom/android/hello/HelloAndroid;",
    access: {Public},
    superclass: SomeType("Landroid/app/Activity;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/android/hello/HelloAndroid;",
            name: "<init>",
            prototype: Prototype(ret: "V", params: @[]),
          ),
          access: {Public, Constructor},
          code: SomeCode(Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Activity;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          )),
        ),
      ],
      virtual_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/android/hello/HelloAndroid;",
            name: "onCreate",
            prototype: Prototype(
              ret: "V",
              params: @["Landroid/os/Bundle;"],
            ),
          ),
          access: {Public},
          code: SomeCode(Code(
            registers: 3,
            ins: 2,
            outs: 2,
            instrs: @[
              invoke_super(1, 2, Method(class: "Landroid/app/Activity;", name: "onCreate",
                prototype: Prototype(ret: "V", params: @["Landroid/os/Bundle;"]))),
              const_high16(0, 0x7f03),
              invoke_virtual(1, 0, Method(class: "Lcom/android/hello/HelloAndroid;", name: "setContentView",
                prototype: Prototype(ret: "V", params: @["I"]))),
              return_void(),
            ],
          )),
        ),
      ],
    )
  )


