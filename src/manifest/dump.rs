//! This package contains a simple parser for binary
//! AndroidManifest.xml files. The output format is intended
//! to be similar to what `aapt dump` would print.

use std::io;

use anyhow::bail;
use num_derive::FromPrimitive;
use num_traits::FromPrimitive;

use crate::util::binparse::little_endian::GetExt;

#[derive(FromPrimitive)]
#[repr(u16)]
pub(crate) enum ChunkType {
    StringPool = 0x0001,
    XML = 0x0003,
    XMLStartNS = 0x0100,
    XMLEndNS = 0x0101,
    XMLStartElement = 0x0102,
    XMLEndElement = 0x0103,
    XMLResourceMap = 0x0180,
}

#[derive(FromPrimitive, Copy, Clone)]
#[repr(u8)]
pub(crate) enum DataType {
    String = 0x03,
    Int = 0x10,
}

pub fn dump(mut r: impl io::Read) -> anyhow::Result<Vec<String>> {
    // File header
    r.expect(ChunkType::XML as u16, "magic header")?;
    let mut out = vec!["Binary XML".to_owned()];
    r.expect(8u16, "header size")?;
    let _ = r.get::<u32>()?; // FIXME: verify chunk size

    // Read "strings pool"
    // Chunk header
    r.expect(ChunkType::StringPool as u16, "string pool header")?;
    r.expect(0x1Cu16, "string pool header size")?;
    let _ = r.get::<u32>()?; // FIXME: verify chunk size
    let n_strings: u32 = r.get()?;
    r.expect(0u32, "style counter")?;
    r.expect(0u32, "flags")?;
    let _ = r.get::<u32>()?; // FIXME: verify strings start
    r.expect(0u32, "styles start")?;
    // Strings offsets
    for _ in 0..n_strings {
        let _ = r.get::<u32>()?; // FIXME: verify strings offsets
    }
    // Read strings
    let mut pool = vec![];
    for _ in 0..n_strings {
        let length: u16 = r.get()?; // FIXME: support long strings
        let mut buf = String::new(); // vec![];
        for _ in 0..length {
            let ch: u16 = r.get()?;
            // FIXME: support full UTF-16
            if ch > 127u16 {
                bail!("non-ASCII (7bit) characters not yet implemented");
            }
            buf.push(ch as u8 as char);
        }
        r.expect(0u16, "string terminator NULL")?;
        pool.push(buf);
    }

    // XXX HACK XXX: dumb very not smart way to eat padding bytes
    let mut r = peekread::BufPeekReader::new(r);
    while skip_if_u8(&mut r, 0)? {
    }

    // Read "XML resources map"
    // Chunk header
    r.expect(ChunkType::XMLResourceMap as u16, "XML resources map header")?;
    r.expect(8u16, "XML resources map header size")?;
    let map_size: u32 = r.get()?;
    let n_res_ids = (map_size - 8) / 4;
    let mut res_ids = vec![];
    for _ in 0..n_res_ids {
        res_ids.push(r.get::<u32>()?);
    }

    // Read "XML nodes"
    let mut prev_line_no = 1u32;
    let mut indent = String::new();
    let mut stack = vec![];
    while !is_eof(&mut r)? {
        let chunk_type: u16 = r.get()?;
        let _header_size: u16 = r.get()?; // FIXME: verify
        let _chunk_size: u32 = r.get()?; // FIXME: verify
        let line_no: u32 = r.get()?;
        r.expect(0xffff_ffffu32, "comment index")?;
        if line_no < prev_line_no {
            bail!("expected increasing line_no, got {line_no} < {prev_line_no}");
        }
        prev_line_no = line_no;
        use ChunkType::*;
        match ChunkType::from_u16(chunk_type) {
            Some(XMLStartNS) => {
                let ns_prefix: u32 = r.get()?;
                let ns_uri: u32 = r.get()?;
                out.push(format!("{indent}N: {}={}",
                    pool[ns_prefix as usize],
                    pool[ns_uri as usize],
                ));
                indent.push_str("  ");
                stack.push(format!("N {ns_prefix:08x} {ns_uri:08x}"));
            }
            Some(XMLEndNS) => {
                let ns_prefix: u32 = r.get()?;
                let ns_uri: u32 = r.get()?;
                let want_stack = format!("N {ns_prefix:08x} {ns_uri:08x}");
                let Some(top) = stack.pop() else {
                    bail!("found XMLEndNS without matching start: {want_stack}");
                };
                if top != want_stack {
                    bail!("found XMLEndNS for {want_stack}, but last XMLStartNS was different: {top}");
                }
                let unindent = indent.len() - 2;
                indent.drain(unindent..);
            }
            Some(XMLStartElement) => {
                let ns: u32 = r.get()?;
                let name: u32 = r.get()?;
                r.expect(0x14u16, "attributes start")?;
                r.expect(0x14u16, "attributes size")?;
                let n_attr: u16 = r.get()?;
                r.expect(0u16, "ID index")?;
                r.expect(0u16, "class index")?;
                r.expect(0u16, "style index")?;
                let mut row = indent.clone() + "E: ";
                if ns != 0xffff_ffffu32 {
                    row.push_str(&(pool[ns as usize].clone() + ":"));
                }
                out.push(row + &pool[name as usize]);
                indent.push_str("  ");
                stack.push(format!("E {ns:08x} {name:08x}"));
                // Attributes
                for _ in 0..n_attr {
                    let ns: u32 = r.get()?;
                    let name: u32 = r.get()?;
                    let raw: u32 = r.get()?;
                    r.expect(8u16, "attr size")?;
                    r.expect(0u8, "res0")?;
                    let data_type: u8 = r.get()?;
                    let data: u32 = r.get()?;
                    let mut row = indent.clone() + "A: ";
                    if ns != 0xffff_ffffu32 {
                        row.push_str(&(pool[ns as usize].clone() + ":"));
                    }
                    row.push_str(&pool[name as usize]);
                    if (name as usize) < res_ids.len() {
                        row.push_str(&format!("(0x{:08x})", res_ids[name as usize]));
                    }
                    row.push_str("=");
                    match DataType::from_u8(data_type) {
                        Some(DataType::String) => row.push_str(&format!("\"{}\"", pool[data as usize])),
                        Some(DataType::Int) => row.push_str(&format!("{}", data)),
                        _ => bail!("unknown attribute type: 0x{data_type:02x}"),
                    }
                    if raw != 0xffff_ffffu32 {
                        row.push_str(&format!(" (Raw: \"{}\")", pool[raw as usize]));
                    }
                    out.push(row);
                }
                indent.push_str("  ");
            }
            Some(XMLEndElement) => {
                let ns: u32 = r.get()?;
                let name: u32 = r.get()?;
                let want_stack = format!("E {ns:08x} {name:08x}");
                let Some(top) = stack.pop() else {
                    bail!("found XMLEndElement without matching start: {want_stack}");
                };
                if top != want_stack {
                    bail!("found XMLEndElement for {want_stack}, but last XMLStartElement was different: {top}");
                }
                let unindent = indent.len() - 4;
                indent.drain(unindent..);
            }
            _ => bail!("unexpected chunk type: 0x{chunk_type:04x}"),
        }
    }
    if stack.len() != 0 {
        bail!("unexpected non-empty stack: {stack:?}");
    }


    Ok(out)
}

fn is_eof(r: &mut impl peekread::PeekRead) -> io::Result<bool> {
    let mut peeker = r.peek();
    let Err(e) = peeker.get::<u8>() else {
        return Ok(false);
    };
    if e.kind() == io::ErrorKind::UnexpectedEof {
        return Ok(true);
    }
    Err(e)
}

fn skip_if_u8(r: &mut impl peekread::PeekRead, skip_if: u8) -> io::Result<bool> {
    {
        let mut peeker = r.peek();
        let v = peeker.get::<u8>()?;
        if v != skip_if {
            return Ok(false);
        }
    }
    r.get::<u8>()?; // TODO: assert that result equals `skip_if`
    Ok(true)
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;
    use crate::util::parse_hex;
    use super::*;
    use pretty_assertions::assert_eq;
    // use pretty_hex::*;

    #[test]
    fn dump_hello_akavel() {
        assert_eq!(
            HELLO_AKAVEL_WANTED_DUMP,
            dump(Cursor::new(parse_hex(HELLO_AKAVEL_BINARY_MANIFEST))).unwrap().join("\n"),
        );
    }

    const HELLO_AKAVEL_BINARY_MANIFEST: &str = r#"
0300 0800 a805 0000 0100 1c00 3c03 0000
1700 0000 0000 0000 0000 0000 7800 0000
0000 0000 0000 0000 2600 0000 5c00 0000
6a00 0000 7600 0000 8800 0000 e000 0000
e400 0000 f600 0000 2a01 0000 5e01 0000
7201 0000 9601 0000 9c01 0000 a401 0000
be01 0000 d401 0000 e801 0000 0602 0000
2402 0000 3402 0000 6c02 0000 8002 0000
1100 6300 6f00 6d00 7000 6900 6c00 6500
5300 6400 6b00 5600 6500 7200 7300 6900
6f00 6e00 0000 1900 6300 6f00 6d00 7000
6900 6c00 6500 5300 6400 6b00 5600 6500
7200 7300 6900 6f00 6e00 4300 6f00 6400
6500 6e00 6100 6d00 6500 0000 0500 6c00
6100 6200 6500 6c00 0000 0400 6e00 6100
6d00 6500 0000 0700 6100 6e00 6400 7200
6f00 6900 6400 0000 2a00 6800 7400 7400
7000 3a00 2f00 2f00 7300 6300 6800 6500
6d00 6100 7300 2e00 6100 6e00 6400 7200
6f00 6900 6400 2e00 6300 6f00 6d00 2f00
6100 7000 6b00 2f00 7200 6500 7300 2f00
6100 6e00 6400 7200 6f00 6900 6400 0000
0000 0000 0700 7000 6100 6300 6b00 6100
6700 6500 0000 1800 7000 6c00 6100 7400
6600 6f00 7200 6d00 4200 7500 6900 6c00
6400 5600 6500 7200 7300 6900 6f00 6e00
4300 6f00 6400 6500 0000 1800 7000 6c00
6100 7400 6600 6f00 7200 6d00 4200 7500
6900 6c00 6400 5600 6500 7200 7300 6900
6f00 6e00 4e00 6100 6d00 6500 0000 0800
6d00 6100 6e00 6900 6600 6500 7300 7400
0000 1000 6300 6f00 6d00 2e00 6100 6b00
6100 7600 6500 6c00 2e00 6800 6500 6c00
6c00 6f00 0000 0100 3900 0000 0200 3200
3800 0000 0b00 6100 7000 7000 6c00 6900
6300 6100 7400 6900 6f00 6e00 0000 0900
4800 6500 6c00 6c00 6f00 4400 6100 6c00
6900 0000 0800 6100 6300 7400 6900 7600
6900 7400 7900 0000 0d00 4800 6500 6c00
6c00 6f00 4100 6300 7400 6900 7600 6900
7400 7900 0000 0d00 6900 6e00 7400 6500
6e00 7400 2d00 6600 6900 6c00 7400 6500
7200 0000 0600 6100 6300 7400 6900 6f00
6e00 0000 1a00 6100 6e00 6400 7200 6f00
6900 6400 2e00 6900 6e00 7400 6500 6e00
7400 2e00 6100 6300 7400 6900 6f00 6e00
2e00 4d00 4100 4900 4e00 0000 0800 6300
6100 7400 6500 6700 6f00 7200 7900 0000
2000 6100 6e00 6400 7200 6f00 6900 6400
2e00 6900 6e00 7400 6500 6e00 7400 2e00
6300 6100 7400 6500 6700 6f00 7200 7900
2e00 4c00 4100 5500 4e00 4300 4800 4500
5200 0000 8001 0800 1800 0000 7205 0101
7305 0101 0100 0101 0300 0101 0001 1000
1800 0000 0200 0000 ffff ffff 0400 0000
0500 0000 0201 1000 8800 0000 0200 0000
ffff ffff ffff ffff 0a00 0000 1400 1400
0500 0000 0000 0000 0500 0000 0000 0000
ffff ffff 0800 0010 1c00 0000 0500 0000
0100 0000 0c00 0000 0800 0003 0c00 0000
ffff ffff 0700 0000 0b00 0000 0800 0003
0b00 0000 ffff ffff 0800 0000 0d00 0000
0800 0010 1c00 0000 ffff ffff 0900 0000
0c00 0000 0800 0010 0900 0000 0201 1000
3800 0000 0400 0000 ffff ffff ffff ffff
0e00 0000 1400 1400 0100 0000 0000 0000
0500 0000 0200 0000 0f00 0000 0800 0003
0f00 0000 0201 1000 3800 0000 0500 0000
ffff ffff ffff ffff 1000 0000 1400 1400
0100 0000 0000 0000 0500 0000 0300 0000
1100 0000 0800 0003 1100 0000 0201 1000
2400 0000 0600 0000 ffff ffff ffff ffff
1200 0000 1400 1400 0000 0000 0000 0000
0201 1000 3800 0000 0700 0000 ffff ffff
ffff ffff 1300 0000 1400 1400 0100 0000
0000 0000 0500 0000 0300 0000 1400 0000
0800 0003 1400 0000 0301 1000 1800 0000
0700 0000 ffff ffff ffff ffff 1300 0000
0201 1000 3800 0000 0800 0000 ffff ffff
ffff ffff 1500 0000 1400 1400 0100 0000
0000 0000 0500 0000 0300 0000 1600 0000
0800 0003 1600 0000 0301 1000 1800 0000
0800 0000 ffff ffff ffff ffff 1500 0000
0301 1000 1800 0000 0900 0000 ffff ffff
ffff ffff 1200 0000 0301 1000 1800 0000
0a00 0000 ffff ffff ffff ffff 1000 0000
0301 1000 1800 0000 0b00 0000 ffff ffff
ffff ffff 0e00 0000 0301 1000 1800 0000
0c00 0000 ffff ffff ffff ffff 0a00 0000
0101 1000 1800 0000 0c00 0000 ffff ffff
0400 0000 0500 0000
"#;

    const HELLO_AKAVEL_WANTED_DUMP: &str = r#"Binary XML
N: android=http://schemas.android.com/apk/res/android
  E: manifest
    A: http://schemas.android.com/apk/res/android:compileSdkVersion(0x01010572)=28
    A: http://schemas.android.com/apk/res/android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
    A: package="com.akavel.hello" (Raw: "com.akavel.hello")
    A: platformBuildVersionCode=28 (Raw: "28")
    A: platformBuildVersionName=9 (Raw: "9")
      E: application
        A: http://schemas.android.com/apk/res/android:label(0x01010001)="HelloDali" (Raw: "HelloDali")
          E: activity
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="HelloActivity" (Raw: "HelloActivity")
              E: intent-filter
                  E: action
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
                  E: category
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")"#;
}
