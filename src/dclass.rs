// TODO: #[macro_export]
macro_rules! dclass {
    // ( $($pub:vis)? $($name:ident).+ ) => {
    ( $($name:ident).+ impl $superclass:ident ) => {
        (
            // $()?
            ("L".to_string() +
                &[ $(stringify!($name)),+ ].join("/")
                + ";"
            , $superclass.clone())
        )
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn bugsnag_apk() {
        let application = "Landroid/app/Application;".to_string();
        let c = dclass! {
            com.bugsnag.dexexample.BugsnagApp impl application
        };
        assert_eq!(c,
            ("Lcom/bugsnag/dexexample/BugsnagApp;".to_string(), application));
    }
}

