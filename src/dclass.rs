// TODO: #[macro_export]
macro_rules! dclass {
    ( $($name:ident).+ ) => {
        (
            "L".to_string() +
                &[ $(stringify!($name)),+ ].join("/")
                + ";"
        )
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn bugsnag_apk() {
        let c = dclass! {
            com.bugsnag.dexexample.BugsnagApp
        };
        assert_eq!(c, "Lcom/bugsnag/dexexample/BugsnagApp;".to_string());
    }
}

