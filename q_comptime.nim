import dali/dex
import dali
import options

static:
  let
    dex = newDex()
    PrintStream = "Ljava/io/PrintStream;"
    String = "Ljava/lang/String;"
  dex.classes.add(ClassDef(
    class: "Lhw;",
    access: {Public},
    superclass: some("Ljava/lang/Object;"),
    class_data: ClassData(
      direct_methods: @[
        EncodedMethod(
          m: Method(
            class: "Lhw;",
            name: "main",
            prototype: Prototype(
              ret: "V",
              params: @["[Ljava/lang/String;"]),
          ),
          access: {Public, Static},
          code: Code(
            registers: 2,
            ins: 1,
            outs: 2,
            instrs: @[
              sget_object(0, Field(class: "Ljava/lang/System;", typ: "Ljava/io/PrintStream;", name: "out")),
              const_string(1, "Hello World!"),
              invoke_virtual(0, 1, jproto PrintStream.println(String)),
              return_void(),
            ])
        )
      ]
    )
  ))
  writeFile("q_comptime.dex", dex.render)

