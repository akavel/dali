use crate::*;

// TODO: #[macro_export]
macro_rules! dclass {
    // ( $($pub:vis)? $($name:ident).+ ) => {
    ( $($name:ident).+ impl $superclass:ident ) => {
        (
            ClassDef {
                class:
                    // $()?
                    "L".to_string() +
                        &[ $(stringify!($name)),+ ].join("/")
                        + ";",
                superclass: Some($superclass.clone()),
                ..Default::default()
            }
        )
    }
}

#[cfg(test)]
mod tests {
    use crate::{instrs::*, *};
    use pretty_assertions::assert_eq;
    use u4::u4;

    #[test]
    fn bugsnag_apk() {
        let application = "Landroid/app/Application;".to_string();
        let c = dclass! {
            com.bugsnag.dexexample.BugsnagApp impl application
        };
        // assert_eq!(c,
        //     ("Lcom/bugsnag/dexexample/BugsnagApp;".to_string(), application));
        assert_eq!(c, ClassDef {
            class: "Lcom/bugsnag/dexexample/BugsnagApp;".to_owned(),
            access: Access::Public.into(),
            superclass: Some("Landroid/app/Application;".to_owned()),
            interfaces: TypeList::default(),
            class_data: Some(ClassData {
                direct_methods: vec![EncodedMethod {
                    m: Method {
                        class: "Lcom/bugsnag/dexexample/BugsnagApp;".to_owned(),
                        name: "<init>".to_owned(),
                        prototype: Prototype {
                            ret: "V".to_owned(),
                            params: vec![],
                        },
                    },
                    access: Access::Public | Access::Constructor,
                    annotations: vec![],
                    code: Some(Code {
                        registers: 1,
                        ins: 1,
                        outs: 1,
                        instrs: vec![
                            invoke_direct1(
                                u4!(0),
                                Method {
                                    class: "Landroid/app/Application;".to_owned(),
                                    name: "<init>".to_owned(),
                                    prototype: Prototype {
                                        ret: "V".to_owned(),
                                        params: vec![],
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
    }
}

