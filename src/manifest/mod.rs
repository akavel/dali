use std::io;

use xmltree::Element as XmlElem;

mod dump;
pub use dump::dump;

pub fn compile(manifest: &XmlElem, w: &mut impl io::Write) -> anyhow::Result<()> {
    Ok(())
}


#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn manifest_based_on_czak_minimal_android_project() {
        let manifest = XmlElem::parse(MANIFEST_XML.as_bytes()).unwrap();
        let mut buf = Vec::<u8>::new();
        compile(&manifest, &mut buf).unwrap();
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
