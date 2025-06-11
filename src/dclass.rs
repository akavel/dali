// TODO: #[macro_export]
macro_rules! dclass {
    (
        $($name:ident).+ impl $superclass:ident {
            #[$($fnmod:ident),+]
            fn <$fn:ident>()
        }
    ) => {
        ClassDef {
            class: dclass!( [class [$($name).+]] ),
            superclass: Some($superclass.clone()),
            class_data: Some(ClassData {
                direct_methods: vec![
                    dclass!( [emethod [$($name).+] [<$fn>] [$($fnmod)+]] ),
                ],
                ..Default::default()
            }),
            ..Default::default()
        }
    };
    // helpers for EncodedMethod building
    ( [emethod [$($c:tt)*] [$($f:tt)*] [Public $($modn:ident)*]] ) => {
        dclass!( [emethod [$($c)*] [$($f)*] [$($modn)*]] ).with_access(Access::Public)
    };
    ( [emethod [$($c:tt)*] [$($f:tt)*] [Constructor $($modn:ident)*]] ) => {
        dclass!( [emethod [$($c)*] [$($f)*] [$($modn)*]] ).with_access(Access::Constructor)
    };
    (
        [emethod [$($class:ident).+] [<$fn:ident>] [] ]
    ) => {
        EncodedMethod {
            m: Method {
                class: dclass!( [class [$($class).+]] ),
                name: "<".to_owned() + stringify!($fn) + ">",
                ..Default::default() // FIXME
            },
            ..Default::default()
        }
    };
    // helper for class name building
    (
        [class [$($class:ident).+]]
    ) => {
        "L".to_owned() +
            &[ $(stringify!($class)),+ ].join("/")
            + ";"
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
            com.bugsnag.dexexample.BugsnagApp impl application {
                #[Public, Constructor]
                fn <init>()
            }
        };
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

