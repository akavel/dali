import unittest
import dali

const
  Application = "Landroid/app/Application;"
  Activity = "Landroid/app/Activity;"
  Bundle = "Landroid/os/Bundle;"
  HelloAndroid = "Lcom/android/hello/HelloAndroid;"

# TODO: test "hello_world.apk":
#   # needs support for arrays, see tdex.nim
# discard dclass hw {.public.}

discard dclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct 0, jproto Application.`<init>`()
    return_void

discard dclass com.android.hello.HelloAndroid {.public.} of Activity:
  proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
    invoke_direct(0, jproto Activity.`<init>`())
    return_void()
  proc fooBar(_: Bundle, _: View, _: int)
  proc onCreate(_: Bundle) {.public, regs:3, ins:2, outs:2.} =
    invoke_super(1, 2, jproto Activity.onCreate(Bundle))
    const_high16(0, 0x7f03)
    invoke_virtual(1, 0, jproto HelloAndroid.setContentView(int))
    return_void()

test "bugsnag.apk":
  let c =
    dclass com.bugsnag.dexexample.BugsnagApp {.public.} of Application:
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
          code: Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Application;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          ),
        )
      ]
    )
  )

test "hello_android.apk":
  let c =
    dclass com.android.hello.HelloAndroid {.public.} of Activity:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:1.} =
        invoke_direct(0, jproto Activity.`<init>`())
        return_void()
      proc onCreate(_: Bundle) {.public, regs:3, ins:2, outs:2.} =
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
          code: Code(
            registers: 1,
            ins: 1,
            outs: 1,
            instrs: @[
              invoke_direct(0, Method(class: "Landroid/app/Activity;", name: "<init>",
                prototype: Prototype(ret: "V", params: @[]))),
              return_void(),
            ],
          ),
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
          code: Code(
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
          ),
        ),
      ],
    )
  )

test "with NimSelf":
  let c =
    dclass com.akavel.HasSelf {.public, nimSelf.}:
      proc `<init>`() {.public, constructor, regs:1, ins:1, outs:0.} =
        return_void()
  checkpoint c.repr
  check c.equals ClassDef(
    class: "Lcom/akavel/HasSelf;",
    superclass: NoType(),
    access: {Public},
    class_data: ClassData(
      instance_fields: @[
        EncodedField(
          f: Field(
            class: "Lcom/akavel/HasSelf;",
            name: "nimSelf",
            typ: "J"),
          access: {Private}),
      ],
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lcom/akavel/HasSelf;",
            name: "<init>",
            prototype: Prototype(ret: "V", params: @[]),
          ),
          access: {Public, Constructor},
          code: Code(
            registers: 1,
            ins: 1,
            outs: 0,
            instrs: @[
              return_void(),
            ],
          ),
        ),
      ],
    )
  )



