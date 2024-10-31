use std::collections::BTreeMap;
use std::io::Write;

use byteorder::{WriteBytesExt, LE};
use enumflags2::{bitflags, BitFlags};
use indexset::BTreeSet;
use num::ToPrimitive;

mod types;
pub use types::*;
mod instrs;

#[derive(Default)]
pub struct Dex {
    // TODO[LATER]: use interned strings instead of String
    strings: BTreeMap<String, u32>, // value: order of addition
    types: BTreeSet<String>,
    // NOTE: prototypes must have no duplicates, TODO: and be sorted by:
    // (ret's type ID; args' type ID)
    prototypes: BTreeSet<Prototype>,
    // NOTE: fields must have no duplicates, TODO: and be sorted by:
    // (class type ID, field name's string ID, field's type ID)
    fields: BTreeSet<Field>,
    // NOTE: methods must have no duplicates, TODO: and be sorted by:
    // (class type ID, name's string ID, prototype's proto ID)
    methods: BTreeSet<Method>,
    classes: Vec<ClassDef>,
}

impl Dex {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add_class(&mut self, c: ClassDef) {
        // Collect strings and all the things from the class
        // (types, prototypes/signatures, fields, methods).
        self.add_type(&c.class);
        if let Some(ref t) = c.superclass {
            self.add_type(t);
        }
        // FIXME: if c.interfaces.len() > 0...
        if let Some(ref cd) = c.class_data {
            for f in &cd.instance_fields {
                self.add_field(&f.f);
            }
            for m in cd.direct_methods.iter().chain(cd.virtual_methods.iter()) {
                self.add_method(&m.m);
                for a in &m.annotations {
                    self.add_type(&a.encoded_annotation.typ);
                    for el in &a.encoded_annotation.elems {
                        self.add_str(&el.name);
                        // FIXME: self.add_enc_value(el.value);
                    }
                }
                let Some(ref code) = m.code else {
                    continue;
                };
                for instr in &code.instrs {
                    for arg in &instr.args {
                        use crate::Arg::*;
                        match arg {
                            FieldXXXX(f) => self.add_field(&f),
                            StringXXXX(s) => self.add_str(&s),
                            TypeXXXX(t) => self.add_type(&t),
                            MethodXXXX(m) => self.add_method(&m),
                            RawX(_) | RawXX(_) | RawXXXX(_) => {}
                            RegX(_) | RegXX(_) => {}
                        }
                    }
                }
            }
            // ...
        }

        self.classes.push(c);
    }

    pub fn render(&self) -> Vec<u8> {
        let mut blob: Vec<u8> = vec![];

        write!(blob, "dex\n035\x00");
        blob.write(&[0u8; 4]); // FIXME: adler_sum slot32
        blob.write(&[0u8; 20]); // FIXME: sha1_sum slotN
        blob.write(&[0u8; 4]); // FIXME: file_size slot32
        blob.write(&0x70u32.to_le_bytes()); // Header size
        blob.write(&0x12345678u32.to_le_bytes()); // Endian constant
        blob.write(&0u32.to_le_bytes()); // link_size
        blob.write(&0u32.to_le_bytes()); // link_off
        blob.write(&[0u8; 4]); // FIXME: map_offset slot32
        blob.write(&self.strings.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: string_ids_off slot32
        blob.write(&self.types.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: type_ids_off slot32
        blob.write(&self.prototypes.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: proto_ids_off slot32
        blob.write(&self.fields.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: field_ids_off slot32
        blob.write(&self.methods.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: method_ids_off slot32
        blob.write(&self.classes.len().to_u32().unwrap().to_le_bytes());
        blob.write(&[0u8; 4]); // FIXME: class_defs_off slot32
        blob.write(&[0u8; 4]); // FIXME: data_size slot32
        blob.write(&[0u8; 4]); // FIXME: data_off slot32

        //-- Partially render string_ids
        // We preallocate space for the list of string offsets. We cannot fill it yet, as its
        // contents will depend on the size of the other segments.
        //FIXME: sections.add (0x0001'u16, blob.pos, dex.strings.len)
        //FIXME: blob[slots.stringIdsOff] = blob.pos
        for i in 0..self.strings.len() {
            blob.write(&[0u8; 4]); // FIXME: string_offs[i] slot32
        }

        //-- Render typeIDs.
        //FIXME: sections.add (0x0002'u16, blob.pos, dex.types.len)
        //FIXME: blob[slots.typeIdsOff] = blob.pos
        let string_ids = self.strings_ordering();
        // self.types are already stored sorted, same as self.strings, so we don't need
        // to sort again by type IDs
        for t in &self.types {
            blob.write_u32::<LE>(*string_ids.get(&self.strings[t]).unwrap());
        }

        //-- Partially render proto IDs.
        // We cannot fill offsets for parameters (type lists), as they'll depend on the size of the
        // segments inbetween.
        //FIXME: sections.add (0x0003'u16, blob.pos, dex.prototypes.len)
        //FIXME: blob[slots.protoIdsOff] = blob.pos
        for p in &self.prototypes {
            let desc = &p.descriptor();
            blob.write_u32::<LE>(*string_ids.get(&self.strings[desc]).unwrap());
            blob.write_u32::<LE>(self.types.rank(&p.ret).to_u32().unwrap());
            blob.write(&[0u8; 4]); // FIXME: type_list_offs[i] slot32
        }

        //-- Render field IDs
        if self.fields.len() > 0 {
            //FIXME: sections.add (0x0004'u16, blob.pos, dex.fields.len)
            //FIXME: blob[slots.fieldIdsOff] = blob.pos
        }
        for f in &self.fields {
            blob.write_u16::<LE>(self.types.rank(&f.class).to_u16().unwrap());
            blob.write_u16::<LE>(self.types.rank(&f.typ).to_u16().unwrap());
            blob.write_u32::<LE>(*string_ids.get(&self.strings[&f.name]).unwrap());
        }

        //-- Render method IDs
        //FIXME: sections.add (0x0005'u16, blob.pos, dex.methods.len)
        //FIXME: if dex.methods.len > 0:
        //FIXME:   blob[slots.methodIdsOff] = blob.pos
        for m in &self.methods {
            blob.write_u16::<LE>(self.types.rank(&m.class).to_u16().unwrap());
            blob.write_u16::<LE>(self.prototypes.rank(&m.prototype).to_u16().unwrap());
            blob.write_u32::<LE>(*string_ids.get(&self.strings[&m.name]).unwrap());
        }

        //-- Partially render class defs.
        //FIXME: sections.add (0x0006'u16, blob.pos, dex.classes.len)
        //FIXME: blob[slots.classDefsOff] = blob.pos
        const NO_INDEX: u32 = 0xffff_ffff;
        for c in &self.classes {
            blob.write_u32::<LE>(self.types.rank(&c.class).to_u32().unwrap());
            blob.write_u32::<LE>(c.access.bits());
            if let Some(ref sup) = c.superclass {
                blob.write_u32::<LE>(self.types.rank(sup).to_u32().unwrap());
            } else {
                blob.write_u32::<LE>(NO_INDEX);
            }
            if c.interfaces.len() > 0 {
                blob.write(&[0u8; 4]); // FIXME: type_list_offsets[...]
            } else {
                blob.write_u32::<LE>(0u32);
            }
            blob.write_u32::<LE>(NO_INDEX); // TODO: source_file_idx
            let has_annotations = if let Some(ref cd) = c.class_data {
                cd.direct_methods
                    .iter()
                    .chain(cd.virtual_methods.iter())
                    .any(|m| m.annotations.len() > 0)
            } else {
                false
            };
            if has_annotations {
                blob.write(&[0u8; 4]); // FIXME: annotation_data_offsets[...]
            } else {
                blob.write(&[0u8; 4]);
            }
            blob.write(&[0u8; 4]); // FIXME: class_data_offsets[...]
            blob.write(&[0u8; 4]); // TODO: static_values
        }

        blob
    }

    fn add_field(&mut self, f: &Field) {
        self.add_type(&f.class);
        self.add_type(&f.typ);
        self.add_str(&f.name);
        self.fields.insert(f.clone());
    }

    fn add_method(&mut self, m: &Method) {
        self.add_type(&m.class);
        self.add_prototype(&m.prototype);
        self.add_str(&m.name);
        self.methods.insert(m.clone());
    }

    fn add_prototype(&mut self, p: &Prototype) {
        self.add_type(&p.ret);
        self.add_type_list(&p.params);
        self.prototypes.insert(p.clone());
        self.add_str(&p.descriptor());
    }

    fn add_type_list(&mut self, ts: &Vec<Type>) {
        if ts.len() == 0 {
            return;
        }
        for t in ts {
            self.add_type(t);
        }
        // FIXME: if ts notin self.type_lists { self.type_lists.add(ts); }
    }

    fn add_type(&mut self, t: &Type) {
        self.add_str(t);
        self.types.insert(t.clone());
    }

    fn add_str(&mut self, s: &String) {
        if s.bytes().any(|c| c == 0 || c >= 0x80) {
            todo!("strings with 0x00 or 0x80..0xFF bytes are not yet supported");
        }
        // "This list must be sorted by string contents, using UTF-16 code point
        // values (not in a locale-sensitive manner), and it must not contain any
        // duplicate entries." [dex-format]
        let n: u32 = self.strings.len().try_into().unwrap();
        self.strings.entry(s.clone()).or_insert(n);
    }

    fn strings_ordering(&self) -> BTreeMap<u32, u32> {
        let mut ordering = BTreeMap::new();
        for (i, added) in self.strings.values().enumerate() {
            ordering.insert(*added, i.try_into().unwrap());
        }
        ordering
    }
}

#[cfg(test)]
mod tests {
    use super::{instrs::*, *};
    use itertools::Itertools;
    use pretty_assertions::assert_eq;
    use pretty_hex::*;
    use u4::u4;

    #[test]
    fn synthesized_hello_world_apk() {
        let mut dex = Dex::new();
        dex.add_class(ClassDef {
            class: "Lhw;".to_owned(),
            access: Access::Public.into(),
            superclass: Some("Ljava/lang/Object;".to_owned()),
            interfaces: TypeList::default(),
            class_data: Some(ClassData {
                direct_methods: vec![EncodedMethod {
                    m: Method {
                        class: "Lhw;".to_owned(),
                        name: "main".to_owned(),
                        prototype: Prototype {
                            ret: "V".to_owned(),
                            params: vec!["[Ljava/lang/String;".to_owned()],
                        },
                    },
                    access: Access::Public | Access::Static,
                    annotations: vec![],
                    code: Some(Code {
                        registers: 2,
                        ins: 1,
                        outs: 2,
                        instrs: vec![
                            sget_object(
                                0,
                                Field {
                                    class: "Ljava/lang/System;".to_owned(),
                                    typ: "Ljava/io/PrintStream;".to_owned(),
                                    name: "out".to_owned(),
                                },
                            ),
                            const_string(1, "Hello World!".to_owned()),
                            invoke_virtual2(
                                u4!(0),
                                u4!(1),
                                Method {
                                    class: "Ljava/io/PrintStream;".to_owned(),
                                    name: "println".to_owned(),
                                    prototype: Prototype {
                                        ret: "V".to_owned(),
                                        params: vec!["Ljava/lang/String;".to_owned()],
                                    },
                                },
                            ),
                            return_void(),
                        ],
                    }),
                }],
                ..Default::default()
            }),
        });
        assert_eq!(
            pretty_hex(&dex.render()),
            pretty_hex(&parse_hex(HELLO_WORLD_APK_HEXDUMP)),
        );
    }

    const HELLO_WORLD_APK_HEXDUMP: &str = "
.d .e .x 0A .0 .3 .5 00  6F 53 89 BC 1E 79 B2 4F
1F 9C 09 66 15 23 2D 3B  56 65 32 C3 B5 81 B4 5A
70 02 00 00 70 00 00 00  78 56 34 12 00 00 00 00
00 00 00 00 DC 01 00 00  0C 00 00 00 70 00 00 00
07 00 00 00 A0 00 00 00  02 00 00 00 BC 00 00 00
01 00 00 00 D4 00 00 00  02 00 00 00 DC 00 00 00
01 00 00 00 EC 00 00 00  64 01 00 00 0C 01 00 00
A6 01 00 00 3A 01 00 00  8A 01 00 00 40 01 00 00
B4 01 00 00 76 01 00 00  54 01 00 00 6C 01 00 00
57 01 00 00 70 01 00 00  A1 01 00 00 C8 01 00 00
01 00 00 00 02 00 00 00  03 00 00 00 04 00 00 00
05 00 00 00 06 00 00 00  08 00 00 00 07 00 00 00
05 00 00 00 34 01 00 00  07 00 00 00 05 00 00 00
2C 01 00 00 04 00 01 00  0A 00 00 00 00 00 01 00
09 00 00 00 01 00 00 00  0B 00 00 00 00 00 00 00
01 00 00 00 02 00 00 00  00 00 00 00 FF FF FF FF
00 00 00 00 D1 01 00 00  00 00 00 00 02 00 01 00
02 00 00 00 00 00 00 00  08 00 00 00 62 00 00 00
1A 01 00 00 6E 20 01 00  10 00 0E 00 01 00 00 00
06 00 00 00 01 00 00 00  03 00 04 .L .h .w .; 00
12 .L .j .a .v .a ./ .l  .a .n .g ./ .O .b .j .e
.c .t .; 00 01 .V 00 13  .[ .L .j .a .v .a ./ .l
.a .n .g ./ .S .t .r .i  .n .g .; 00 02 .V .L 00
04 .m .a .i .n 00 12 .L  .j .a .v .a ./ .l .a .n
.g ./ .S .y .s .t .e .m  .; 00 15 .L .j .a .v .a
./ .i .o ./ .P .r .i .n  .t .S .t .r .e .a .m .;
00 03 .o .u .t 00 0C .H  .e .l .l .o 20 .W .o .r
.l .d .! 00 12 .L .j .a  .v .a ./ .l .a .n .g ./
.S .t .r .i .n .g .; 00  07 .p .r .i .n .t .l .n
00 00 00 01 00 00 09 8C  02 00 00 00 0C 00 00 00
00 00 00 00 01 00 00 00  00 00 00 00 01 00 00 00
0C 00 00 00 70 00 00 00  02 00 00 00 07 00 00 00
A0 00 00 00 03 00 00 00  02 00 00 00 BC 00 00 00
04 00 00 00 01 00 00 00  D4 00 00 00 05 00 00 00
02 00 00 00 DC 00 00 00  06 00 00 00 01 00 00 00
EC 00 00 00 01 20 00 00  01 00 00 00 0C 01 00 00
01 10 00 00 02 00 00 00  2C 01 00 00 02 20 00 00
0C 00 00 00 3A 01 00 00  00 20 00 00 01 00 00 00
D1 01 00 00 00 10 00 00  01 00 00 00 DC 01 00 00
    ";

    const BUGSNAG_SAMPLE_APK_HEXDUMP: &str = "
6465780A 30333800 7A44CBBB FB4AE841 0286C06A 8DF19000
3C5DE024 D07326A2 E0010000 70000000 78563412 00000000
00000000 64010000 05000000 70000000 03000000 84000000
01000000 90000000 00000000 00000000 02000000 9C000000
01000000 AC000000 14010000 CC000000 E4000000 EC000000
07010000 2C010000 2F010000 01000000 02000000 03000000
03000000 02000000 00000000 00000000 00000000 01000000
00000000 01000000 01000000 00000000 00000000 FFFFFFFF
00000000 57010000 00000000 01000100 01000000 00000000
04000000 70100000 00000E00 063C696E 69743E00 194C616E
64726F69 642F6170 702F4170 706C6963 6174696F 6E3B0023
4C636F6D 2F627567 736E6167 2F646578 6578616D 706C652F
42756773 6E616741 70703B00 01560026 7E7E4438 7B226D69
6E2D6170 69223A32 362C2276 65727369 6F6E223A 2276302E
312E3134 227D0000 00010001 818004CC 01000000 0A000000
00000000 01000000 00000000 01000000 05000000 70000000
02000000 03000000 84000000 03000000 01000000 90000000
05000000 02000000 9C000000 06000000 01000000 AC000000
01200000 01000000 CC000000 02200000 05000000 E4000000
00200000 01000000 57010000 00100000 01000000 64010000
    ";

    const HELLO_ANDROID_APK_HEXDUMP: &str = "
6465 780a 3033 3500 2f4f 153b 3623 8747
6d02 4697 5b1e 959d a8b1 2f0f 9c3a a14f
7802 0000 7000 0000 7856 3412 0000 0000
0000 0000 f001 0000 0a00 0000 7000 0000
0500 0000 9800 0000 0300 0000 ac00 0000
0000 0000 0000 0000 0500 0000 d000 0000
0100 0000 f800 0000 6001 0000 1801 0000
6201 0000 6a01 0000 6d01 0000 8501 0000
9a01 0000 bc01 0000 bf01 0000 c301 0000
c701 0000 d101 0000 0100 0000 0200 0000
0300 0000 0400 0000 0500 0000 0500 0000
0400 0000 0000 0000 0600 0000 0400 0000
5401 0000 0700 0000 0400 0000 5c01 0000
0100 0000 0000 0000 0100 0200 0800 0000
0300 0000 0000 0000 0300 0200 0800 0000
0300 0100 0900 0000 0300 0000 0100 0000
0100 0000 0000 0000 ffff ffff 0000 0000
e101 0000 0000 0000 0100 0100 0100 0000
0000 0000 0400 0000 7010 0000 0000 0e00
0300 0200 0200 0000 0000 0000 0900 0000
6f20 0100 2100 1500 037f 6e20 0400 0100
0e00 0000 0100 0000 0000 0000 0100 0000
0200 063c 696e 6974 3e00 0149 0016 4c61
6e64 726f 6964 2f61 7070 2f41 6374 6976
6974 793b 0013 4c61 6e64 726f 6964 2f6f
732f 4275 6e64 6c65 3b00 204c 636f 6d2f
616e 6472 6f69 642f 6865 6c6c 6f2f 4865
6c6c 6f41 6e64 726f 6964 3b00 0156 0002
5649 0002 564c 0008 6f6e 4372 6561 7465
000e 7365 7443 6f6e 7465 6e74 5669 6577
0000 0001 0102 8180 0498 0203 01b0 0200
0b00 0000 0000 0000 0100 0000 0000 0000
0100 0000 0a00 0000 7000 0000 0200 0000
0500 0000 9800 0000 0300 0000 0300 0000
ac00 0000 0500 0000 0500 0000 d000 0000
0600 0000 0100 0000 f800 0000 0120 0000
0200 0000 1801 0000 0110 0000 0200 0000
5401 0000 0220 0000 0a00 0000 6201 0000
0020 0000 0100 0000 e101 0000 0010 0000
0100 0000 f001 0000
    ";

    fn parse_hex(s: &str) -> Vec<u8> {
        fn parse_nibble(c: u8) -> u8 {
            match c {
                b'0'..=b'9' => c - b'0',
                b'a'..=b'f' => c - b'a' + 0xa,
                b'A'..=b'F' => c - b'A' + 0xa,
                _ => panic!("not a hex digit: '{}'", c as char),
            }
        }
        s.bytes()
            .filter(|b| !b.is_ascii_whitespace())
            .tuples::<(_, _)>()
            .map(|tup| match tup {
                (b'.', c) => c,
                (hi, lo) => parse_nibble(hi) << 4 | parse_nibble(lo),
            })
            .collect()
    }
}
