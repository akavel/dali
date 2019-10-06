{.experimental: "codeReordering".}
import hashes

import patty


variantp Arg:  # Argument of an instruction of Dalvik bytecode
  RawX(raw4: uint4)
  RawXX(raw8: uint8)
  RawXXXX(raw16: uint16)
  RegX(reg4: uint4)
  RegXX(reg8: uint8)
  FieldXXXX(field16: Field)
  StringXXXX(string16: String)
  TypeXXXX(type16: Type)
  MethodXXXX(method16: Method)

variantp MaybeType:
  SomeType(typ: Type)
  NoType

variantp MaybeCode:
  SomeCode(code: Code)
  NoCode


type
  Field* = ref object
    class*: Type
    typ*: Type
    name*: String
  Type* = String
  String* = string
  Method* = ref object
    class*: Type
    prototype*: Prototype  # a.k.a. method signature
    name*: String
  Prototype* = ref object
    ret*: Type
    params*: TypeList
  TypeList* = seq[Type]

  uint4* = range[0..15]   # e.g. register v0..v15

func equals*(a, b: Method): bool =
  a.class == b.class and a.name == b.name and a.prototype.equals(b.prototype)
func equals*(a, b: Prototype): bool =
  a.ret == b.ret and a.params == b.params

type
  Instr* = ref object
    opcode*: uint8
    args*: seq[Arg]
  Code* = ref object
    registers*: uint16
    ins*: uint16
    outs*: uint16 # "the number of words of outgoing argument space required by this code for method invocation"
    # tries: ?
    # debug_info: ?
    instrs*: seq[Instr]

type
  ClassDef* = ref object
    class*: Type
    access*: set[Access]
    superclass*: MaybeType
    # interfaces: TypeList
    # sourcefile: String
    # annotations: ?
    class_data*: ClassData
    # static_values: ?
  ClassData* = ref object
    # static_fields*: ?
    # instance_fields*: ?
    direct_methods*: seq[EncodedMethod]
    virtual_methods*: seq[EncodedMethod]
  EncodedMethod* = ref object
    m*: Method
    access*: set[Access]
    code*: MaybeCode
  Access* = enum
    Public = 0x1
    Private = 0x2
    Protected = 0x4
    Static = 0x8
    Final = 0x10
    Synchronized = 0x20
    Varargs = 0x80
    Native = 0x100
    Interface = 0x200
    Abstract = 0x400
    Annotation = 0x2000
    Enum = 0x4000
    Constructor = 0x1_0000

  NotImplementedYetError* = object of CatchableError
  ConsistencyError* = object of CatchableError

proc hash*(proto: Prototype): Hash =
  var h: Hash = 0
  h = h !& hash(proto.ret)
  h = h !& hash(proto.params)
  result = !$h
func equals[T](a, b: seq[T]): bool =
  if a.len != b.len: return false
  for i in 0..<a.len:
    if not a[i].equals(b[i]): return false
  return true
func equals*(a, b: Arg): bool =
  if a == b: return true
  if a.kind == b.kind:
    case a.kind
    of ArgKind.MethodXXXX: return a.method16.equals(b.method16)
    else: return false
  return false
func equals*(a, b: Instr): bool =
  a.opcode == b.opcode and a.args.equals(b.args)
func equals*(a, b: Code): bool =
  a.registers == b.registers and a.ins == b.ins and a.outs == b.outs and a.instrs.equals(b.instrs)
func equals*(a, b: MaybeCode): bool =
  a.kind == b.kind and (a.kind == MaybeCodeKind.NoCode or a.code.equals(b.code))
func equals*(a, b: EncodedMethod): bool =
  a.m.equals(b.m) and a.access == b.access and a.code.equals(b.code)
func equals*(a, b: ClassData): bool =
  a.direct_methods.equals(b.direct_methods) and a.virtual_methods.equals(b.virtual_methods)
func equals*(a, b: ClassDef): bool =
  a.class == b.class and a.access == b.access and a.superclass == b.superclass and a.class_data.equals(b.class_data)
