//! This package contains a simple parser for binary
//! AndroidManifest.xml files. The output format is intended
//! to be similar to what `aapt dump` would print.

use std::io::BufRead;

use bytesutil::ReadExt;

use crate::util::binparse::little_endian::GetExt;

#[repr(u16)]
pub enum ChunkType {
    StringPool = 0x0001,
    XML = 0x0003,
    XMLStartNS = 0x0100,
    XMLEndNS = 0x0101,
    XMLStartElement = 0x0102,
    XMLEndElement = 0x0103,
    XMLResourceMap = 0x0180,
}

pub fn dump(mut r: impl BufRead) -> anyhow::Result<Vec<String>> {
    // TODO: try using some parser helper tool


    // File header
    r.expect(ChunkType::XML as u16, "magic header")?;
    // expect_le(&mut r, ChunkType::XML as u16, "magic header")?;
    let mut out = vec!["Binary XML\n".to_owned()];
    r.expect(8u16, "header size")?;
    // expect_le(&mut r, 8u16, "header size")?;
    let _ = r.get::<u32>()?; // FIXME: verify chunk size

    // Read "strings pool"
    // Chunk header

    Ok(out)
}

// fn expect_le<T: bytesutil::ReadFrom>(r: &mut impl BufRead, want: T, name: &str) -> Result<()> {
//     let got = r.read_le::<T>()?;
//     if got != want {
//         bail!("{name} mismatch, want 0x{want:#02x}, got: 0x{got:#02x}");
//     }
//     Ok(())
// }

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
            dump(Cursor::new(parse_hex(HELLO_AKAVEL_BINARY_MANIFEST))).unwrap().join("\n"),
            HELLO_AKAVEL_WANTED_DUMP,
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
N: android=http://schemas.android.com/apk/res/android (line=2)
  E: manifest (line=2)
    A: http://schemas.android.com/apk/res/android:compileSdkVersion(0x01010572)=28
    A: http://schemas.android.com/apk/res/android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
    A: package="com.akavel.hello" (Raw: "com.akavel.hello")
    A: platformBuildVersionCode=28 (Raw: "28")
    A: platformBuildVersionName=9 (Raw: "9")
      E: application (line=4)
        A: http://schemas.android.com/apk/res/android:label(0x01010001)="HelloDali" (Raw: "HelloDali")
          E: activity (line=5)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="HelloActivity" (Raw: "HelloActivity")
              E: intent-filter (line=6)
                  E: action (line=7)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
                  E: category (line=8)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")"#;
}
