use std::io;
use std::collections::{BTreeMap, BTreeSet};

use anyhow::bail;
use roxmltree::Node as Xml;

mod dump;
pub use dump::dump;
use dump::{ChunkType, DataType};
use crate::util::*;

pub fn compile(xml: &Xml) -> anyhow::Result<Vec<u8>> {
    // Parse + verify namespaces in a dumb, hacky way
    if xml.tag_name().name() != "manifest" {
        bail!("root node must be <manifest>, got: {}", xml.tag_name().name());
    }
    const NS_ANDROID: &str = "http://schemas.android.com/apk/res/android";
    let ns = xml.namespaces().collect::<Vec<&roxmltree::Namespace>>();
    if ns.len() != 1 || ns[0].name() != Some("android") || ns[0].uri() != NS_ANDROID {
        bail!("the <manifest> node must have 'xmlns:android' attribute with namespace {NS_ANDROID:?}");
    }

    // Collect all strings
    let (resources, non_resources) = collect_strings(xml);
    let mut strings = Vec::<String>::new();
    let mut strings_map = BTreeMap::<String, u32>::new();
    for s in resources.into_iter() {
        strings_map.insert(s.clone(), strings.len().try_into().unwrap());
        strings.push(s);
    }
    for s in non_resources.into_iter() {
        strings_map.insert(s.clone(), strings.len().try_into().unwrap());
        strings.push(s);
    }

    // Partially render header
    let mut blob = Vec::<u8>::new();
    blob.put_u16(ChunkType::XML as u16);
    blob.put_u16(8u16); // header size
    let file_size = blob.slot32();

    // Render list of strings
    let strings_pos = blob.len();
    blob.put_u16(ChunkType::StringPool as u16);
    blob.put_u16(0x1Cu16); // header size
    let strings_size = blob.slot32();
    blob.put_u32(strings.len().try_into().unwrap());
    blob.put_u32(0u32); // style count
    blob.put_u32(0u32); // flags TODO(akavel): try writing utf-8, not utf-16
    let strings_start = blob.slot32();
    blob.put_u32(0u32); // styles start
    let mut string_offsets = Vec::<Slot32>::new();
    for _ in 0..strings.len() {
        string_offsets.push(blob.slot32());
    }
    let strings_start_pos = blob.len();
    blob.set(strings_start, (strings_start_pos - strings_pos).try_into().unwrap());
    for (s, slot) in strings.into_iter().zip(string_offsets) {
        blob.set(slot, (blob.len() - strings_start_pos).try_into().unwrap());
        blob.put_u16(s.len().try_into().unwrap()); // TODO: handle longer strings
        for b in s.bytes() {
            // FIXME: proper UTF handling (ideally UTF-8)
            blob.put_u16(b as u16);
        }
        blob.put_u16(0u16);
    }
    blob.pad32(); // Note: when chunk size was not rounded to 4 bytes, I got a validation error
    blob.set(strings_size, (blob.len() - strings_pos).try_into().unwrap());

    Ok(blob)
}

fn collect_strings(xml: &Xml) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut resources = BTreeSet::new();
    let mut other = BTreeSet::new();
    let known_resources = known_resources(); // TODO[LATER]: make a static/const map
    let mut insert = |s: String| {
    // fn insert(s: String) {
        if known_resources.contains_key(&s.as_str()) {
            resources.insert(s);
        } else {
            other.insert(s);
        }
    };
    for xml in xml.descendants() {
        insert(xml.tag_name().name().to_owned());
        for a in xml.attributes() {
            // TODO: handle namespaces & namespace definitions
            // (xmlns) properly
            insert(a.name().to_owned());
            insert(a.value().to_owned());
        }
    }
    (resources, other)
}

fn known_resources() -> BTreeMap<&'static str, u32> {
    BTreeMap::from([
        ("compileSdkVersion", 0x01010572u32),
        ("compileSdkVersionCodename", 0x01010573u32),
        ("label", 0x01010001u32),
        ("name", 0x01010003u32),
    ])
}


#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn manifest_based_on_czak_minimal_android_project() {
        let manifest = roxmltree::Document::parse(MANIFEST_XML).unwrap();
        let buf = compile(&manifest.root_element()).unwrap();
        assert_eq!(
            MANIFEST_DUMP,
            dump(&*buf).unwrap().join("\n"),
        );
    }

    const MANIFEST_XML: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.akavel.hello">
    <application android:label="HelloDali">
        <activity android:name="HelloActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
"#;

    const MANIFEST_DUMP: &str = r#"
Binary XML
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
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
"#;
}
