// TODO: #[macro_export]
macro_rules! dclass {
    (
        $($name:ident).+ impl $superclass:ident {
            $($classbody:tt)*
        }
    ) => {
        dclass!( [classdef
            [$($classbody)*]
            [$($name).+]
            [$superclass]
        ])
    };
    // helpers for ClassDef building
    (
        [classdef
            [
                #[$( $fnmod:ident $(($modarg:literal))? ),+]
                fn <$fn:ident>( $($args:tt)* ) $(-> $ret:ident)? {
                    $( $instr:ident( $($iargs:tt)* ) )+
                }
                $($classbody:tt)*
            ]
            [$($name:ident).+]
            [$superclass:ident]
        ]
    ) => {
        dclass!( [classdef
            [$($classbody)*]
            [$($name).+]
            [$superclass]
        ]).with_method( dclass!( [emethod
            [$( $fnmod $(($modarg))? )+]
            [$($name).+]
            ["<".to_owned() + stringify!($fn) + ">"]
            [$($args)*]
            [$($ret)?]
            [$( $instr( $($iargs)* ) )+]
        ]))
    };
    (
        [classdef
            [
                #[$( $fnmod:ident $(($modarg:literal))? ),+]
                fn $fn:ident ( $($args:tt)* ) $(-> $ret:ident)? {
                    $( $instr:ident( $($iargs:tt)* ) )+
                }
                $($classbody:tt)*
            ]
            [$($name:ident).+]
            [$superclass:ident]
        ]
    ) => {
        dclass!( [classdef
            [$($classbody)*]
            [$($name).+]
            [$superclass]
        ]).with_method( dclass!( [emethod
            [$( $fnmod $(($modarg))? )+]
            [$($name).+]
            [stringify!($fn).to_owned()]
            [$($args)*]
            [$($ret)?]
            [$( $instr( $($iargs)* ) )+]
        ]))
    };
    (
        [classdef
            [ ]
            [$($name:ident).+]
            [$superclass:ident]
        ]
    ) => {
        ClassDef {
            class: dclass!( [class [$($name).+]] ),
            access: Access::Public.into(),
            superclass: Some($superclass.clone()),
            ..Default::default()
        }
    };
    // helpers for EncodedMethod building
    ( [emethod [Public $($fnmod:tt)*] $([$($rest:tt)*])*] ) => {
        dclass!( [emethod [$($fnmod)*] $([$($rest)*])*] ).with_access(Access::Public)
    };
    ( [emethod [Constructor $($fnmod:tt)*] $([$($rest:tt)*])*] ) => {
        dclass!( [emethod [$($fnmod)*] $([$($rest)*])*] ).with_access(Access::Constructor)
    };
    ( [emethod [Regs($n:literal) $($fnmod:tt)*] $([$($rest:tt)*])*] ) => {
        dclass!( [emethod [$($fnmod)*] $([$($rest)*])*] ).with_registers($n as u16)
    };
    ( [emethod [Ins($n:literal) $($fnmod:tt)*] $([$($rest:tt)*])*] ) => {
        dclass!( [emethod [$($fnmod)*] $([$($rest)*])*] ).with_ins($n as u16)
    };
    ( [emethod [Outs($n:literal) $($fnmod:tt)*] $([$($rest:tt)*])*] ) => {
        dclass!( [emethod [$($fnmod)*] $([$($rest)*])*] ).with_outs($n as u16)
    };
    (
        [emethod
            []
            [$($class:ident).+]
            [$fn:expr]
            [$($args:tt)*]
            [$($ret:ident)?]
            [$( $instr:ident( $($iargs:tt)* ) )+]]
    ) => {
        EncodedMethod {
            m: Method {
                class: dclass!( [class [$($class).+]] ),
                name: $fn,
                prototype: Prototype {
                    params: vec![$($args.clone())*],
                    ret: dclass!( [ret [$($ret)?]] ),
                },
            },
            code: Some(Code {
                instrs: vec![
                    $(
                        dclass!( [iargs $instr [, $($iargs)*]] )
                    ),+
                ],
                ..Default::default()
            }),
            ..Default::default()
        }
    };
    // helper for Instr args building
    ( [iargs $i:ident [, $v:expr $(, $($in:tt)* )? ] $([$($out:tt)*])*] ) => {
        dclass!( [iargs $i [, $( $($in)* )?] $([$($out)*])* [$v]] )
    };
    ( [iargs $i:ident [, @ $($proto:tt)*] $([$($out:tt)*])*] ) => {
        dclass!( [iargs $i [,] $([$($out)*])* [jproto!( $($proto)* )]] )
    };
    ( [iargs $i:ident [,] $([$($out:tt)*])*] ) => {
        $i ( $($($out)*),* )
    };
    // helper for return type name building
    ( [ret []] ) => {
        "V".to_owned()
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

// TODO: #[macro_export]
macro_rules! jproto {
    ( $class:ident . <$fn:ident> ( $($arg:ident),* ) ) => {
        Method {
            class: $class.clone(),
            name: "<".to_owned() + stringify!($fn) + ">",
            prototype: Prototype {
                ret: "V".to_owned(),
                params: vec![ $($arg.clone()),* ],
            },
        }
    };
    ( $class:ident . $fn:ident ( $($arg:ident),* ) ) => {
        Method {
            class: $class.clone(),
            name: stringify!($fn).to_owned(),
            prototype: Prototype {
                ret: "V".to_owned(),
                params: vec![ $($arg.clone()),* ],
            },
        }
    };
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
                #[Public, Constructor, Regs(1), Ins(1), Outs(1)]
                fn <init>() {
                    invoke_direct1(u4!(0), @application.<init>())
                    return_void()
                }
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

    #[test]
    fn hello_android_apk() {
        let activity = "Landroid/app/Activity;".to_owned();
        let bundle = "Landroid/os/Bundle;".to_owned();
        let hello_android = "Lcom/android/hello/HelloAndroid;".to_owned();
        let int = "I".to_owned();
        let c = dclass! {
            com.android.hello.HelloAndroid impl activity {
                #[Public, Constructor, Regs(1), Ins(1), Outs(1)]
                fn <init>() {
                    invoke_direct1(u4!(0), @activity.<init>())
                    return_void()
                }
                #[Public, Regs(3), Ins(2), Outs(2)]
                fn onCreate(bundle) {
                    invoke_super2(u4!(1), u4!(2), @activity.onCreate(bundle))
                    const_high16(0, 0x7f03)
                    invoke_virtual2(u4!(1), u4!(0), @hello_android.setContentView(int))
                    return_void()
                }
            }
        };
        assert_eq!(c, ClassDef {
            class: "Lcom/android/hello/HelloAndroid;".to_owned(),
            access: Access::Public.into(),
            superclass: Some("Landroid/app/Activity;".to_owned()),
            interfaces: TypeList::default(),
            class_data: Some(ClassData {
                direct_methods: vec![EncodedMethod {
                    m: Method {
                        class: "Lcom/android/hello/HelloAndroid;".to_owned(),
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
                                    class: "Landroid/app/Activity;".to_owned(),
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
                virtual_methods: vec![EncodedMethod {
                    m: Method {
                        class: "Lcom/android/hello/HelloAndroid;".to_owned(),
                        name: "onCreate".to_owned(),
                        prototype: Prototype {
                            ret: "V".to_owned(),
                            params: vec!["Landroid/os/Bundle;".to_owned()],
                        },
                    },
                    access: Access::Public.into(),
                    annotations: vec![],
                    code: Some(Code {
                        registers: 3,
                        ins: 2,
                        outs: 2,
                        instrs: vec![
                            invoke_super2(u4!(1), u4!(2), Method {
                                class: "Landroid/app/Activity;".to_owned(),
                                name: "onCreate".to_owned(),
                                prototype: Prototype {
                                    ret: "V".to_owned(),
                                    params: vec!["Landroid/os/Bundle;".to_owned()],
                                },
                            }),
                            const_high16(0, 0x7f03),
                            invoke_virtual2(u4!(1), u4!(0), Method {
                                class: "Lcom/android/hello/HelloAndroid;".to_owned(),
                                name: "setContentView".to_owned(),
                                prototype: Prototype {
                                    ret: "V".to_owned(),
                                    params: vec!["I".to_owned()],
                                },
                            }),
                            return_void(),
                        ],
                    }),
                }],
                ..Default::default()
            }),
        });
    }
}

