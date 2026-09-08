#![forbid(unsafe_op_in_unsafe_fn)]
#![deny(clippy::all)]

pub mod ffi;
pub mod keyboard;
pub mod model;
pub mod modes;
pub mod protocol;
pub mod recording;
pub mod storage;

pub use model::{AppData, ConnectionRecord, SavedWatch, WatchButtonEvent, WatchSnapshot};
