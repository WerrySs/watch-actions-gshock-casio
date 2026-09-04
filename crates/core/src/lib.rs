#![forbid(unsafe_op_in_unsafe_fn)]
#![deny(clippy::all)]

pub mod ffi;
pub mod model;
pub mod protocol;
pub mod storage;

pub use model::{AppData, ConnectionRecord, SavedWatch, WatchButtonEvent, WatchSnapshot};
