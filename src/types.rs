use enumflags2::{bitflags, BitFlags};
pub use u4::U4;

pub type Type = String;
pub type TypeList = Vec<Type>;

pub struct ClassDef {
    pub class: Type,
    pub access: BitFlags<Access>,
    pub superclass: Option<Type>,
    pub interfaces: TypeList,
    // sourcefile: String,
    // annotations: ?
    pub class_data: Option<ClassData>,
    // static_values: ?
}

#[bitflags]
#[repr(u32)]
#[derive(Copy, Clone, Debug, PartialEq)]
pub enum Access {
    Public = 0x1,
    Private = 0x2,
    Protected = 0x4,
    Static = 0x8,
    Final = 0x10,
    Synchronized = 0x20,
    Varargs = 0x80,
    Native = 0x100,
    Interface = 0x200,
    Abstract = 0x400,
    Annotation = 0x2000,
    Enum = 0x4000,
    Constructor = 0x1_0000,
}

#[derive(Default)]
pub struct ClassData {
    // static_fields: ?
    // TODO: add some tests for rendered instance_fields
    pub instance_fields: Vec<EncodedField>,
    pub direct_methods: Vec<EncodedMethod>,
    pub virtual_methods: Vec<EncodedMethod>,
}

pub struct EncodedField {
    pub f: Field,
    pub access: BitFlags<Access>,
}

pub struct EncodedMethod {
    pub m: Method,
    pub access: BitFlags<Access>,
    pub annotations: Vec<AnnotationItem>,
    pub code: Option<Code>,
}

pub struct AnnotationItem {
    pub visibility: Visibility,
    pub encoded_annotation: EncodedAnnotation,
}

pub enum Visibility {
    System = 0x02,
}

pub struct EncodedAnnotation {
    pub typ: Type,
    pub elems: Vec<AnnotationElement>,
}

pub struct AnnotationElement {
    pub name: String,
    pub value: EncodedValue,
}

pub struct Field {
    pub class: Type,
    pub typ: Type,
    pub name: String,
}

pub struct Method {
    pub class: Type,
    pub prototype: Prototype, // a.k.a. method signature
    pub name: String,
}

pub struct Prototype {
    pub ret: Type,
    pub params: TypeList,
}

impl Prototype {
    pub(crate) fn descriptor(&self) -> String {
        fn type_char(t: &Type) -> char {
            match t.as_bytes() {
                b @ [b'V' | b'Z' | b'B' | b'S' | b'C' | b'I' | b'J' | b'F' | b'D'] => b[0] as char,
                [b'[' | b'L', ..] => 'L',
                _ => panic!("unexpected type in prototype: {t:?}"),
            }
        }
        Some(&self.ret)
            .into_iter()
            .chain(self.params.iter())
            .map(type_char)
            .collect()
    }
}

pub struct Instr {
    pub opcode: u8,
    // NOTE: We're assuming little endian encoding of the
    // file here; 8-bit args should be ordered in
    // "swapped order" vs. the one listed in official
    // Android bytecode spec (i.e., add lower byte first,
    // higher byte later). On the other hand, 16-bit
    // words should not have contents rotated (just fill
    // them as in the spec).
    pub args: Vec<Arg>,
}

pub struct Code {
    pub registers: u16,
    pub ins: u16,
    pub outs: u16, // "the number of words of outgoing argument space required by this code for method invocation"
    // tries: ?
    // debug_info: ?
    pub instrs: Vec<Instr>,
}

pub enum Arg {
    RawX(U4),
    RawXX(u8),
    RawXXXX(u16),
    RegX(U4),
    RegXX(u8),
    FieldXXXX(Field),
    StringXXXX(String),
    TypeXXXX(Type),
    MethodXXXX(Method),
}

pub enum EncodedValue {
    Type(Type),
    Array(Vec<EncodedValue>),
}
