pub use bytesutil::{ReadExt, ReadFrom};
use thiserror::Error;
use std::{fmt, io};

#[derive(Error, Debug)]
pub enum ExpectError<T: fmt::LowerHex> {
    #[error("{name} mismatch, expected 0x{expected:x}, got: 0x{actual:x}")]
    Mismatch {
        name: &'static str,
        expected: T,
        actual: T,
    },
    #[error("cannot read {name}")]
    Io {
        #[source] source: io::Error,
        name: &'static str,
    },
}

pub mod little_endian {
    use super::*;
    use std::io::Result as IoResult;

    pub trait GetExt {
        fn get<T: ReadFrom>(&mut self) -> IoResult<T>;
        // fn get_named<T: ReadFrom>(&mut self, name: &str) -> NamedIoResult<T>;
        fn expect<T: ReadFrom + PartialEq + fmt::LowerHex>(&mut self, expected: T, name: &'static str) -> Result<(), ExpectError<T>>;
    }

    impl<R: ReadExt> GetExt for R {
        fn get<T: ReadFrom>(&mut self) -> IoResult<T> {
            self.read_le()
        }

        fn expect<T: ReadFrom + PartialEq + fmt::LowerHex>(&mut self, expected: T, name: &'static str) -> Result<(), ExpectError<T>> {
            let actual = match self.get::<T>() {
                Err(source) => return Err(ExpectError::Io { source, name }),
                Ok(v) => v,
            };
            if actual == expected {
                Ok(())
            } else {
                Err(ExpectError::Mismatch { name, expected, actual })
            }
        }
    }
}

// #[cfg(test)]
// mod tests {
//     use super::*;

//     #[test]
//     fn it_works() {
//         let result = add(2, 2);
//         assert_eq!(result, 4);
//     }
// }

