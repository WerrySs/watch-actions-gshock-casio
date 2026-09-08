use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::slice;

use chrono::{Local, TimeZone as _};
use serde::Serialize;

use crate::model::{
    AppData, WatchButtonEvent, model_from_bluetooth_name, normalize_model, sanitize_single_line,
};
use crate::protocol;

const CORE_VERSION: &CStr = c"0.1.0";
const MAXIMUM_FFI_STRING_BYTES: usize = 10_000_000;

#[unsafe(no_mangle)]
/// Checks the supported model allowlist.
///
/// # Safety
/// `value` must be null or a readable NUL-terminated string for this call.
pub unsafe extern "C" fn wb_is_supported_model(value: *const c_char) -> bool {
    (unsafe { read_c_string(value) }).is_some_and(|v| crate::model::is_supported_model(&v))
}

#[unsafe(no_mangle)]
/// Checks an advertised name before a Bluetooth session is started.
///
/// # Safety
/// `value` must be null or a readable NUL-terminated string for this call.
pub unsafe extern "C" fn wb_is_supported_bluetooth_name(value: *const c_char) -> bool {
    (unsafe { read_c_string(value) }).is_some_and(|v| crate::model::is_supported_bluetooth_name(&v))
}

#[repr(C)]
pub struct WbBytes {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl WbBytes {
    fn from_vec(mut bytes: Vec<u8>) -> Self {
        let result = Self {
            data: bytes.as_mut_ptr(),
            len: bytes.len(),
            capacity: bytes.capacity(),
        };
        std::mem::forget(bytes);
        result
    }

    const fn empty() -> Self {
        Self {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JsonResult<T: Serialize> {
    ok: bool,
    value: Option<T>,
    error: Option<String>,
}

#[unsafe(no_mangle)]
pub extern "C" fn wb_core_version() -> *const c_char {
    CORE_VERSION.as_ptr()
}

#[unsafe(no_mangle)]
/// Returns the shared physical-key catalog. Release with `wb_string_free`.
pub extern "C" fn wb_keyboard_catalog_json() -> *mut c_char {
    into_c_string(serde_json::to_string(crate::keyboard::KEYS).unwrap_or_else(|_| "[]".to_owned()))
}

#[unsafe(no_mangle)]
/// Reduces bounded, explicitly supplied key transitions; never observes the system keyboard.
/// Release the result with `wb_string_free`.
/// # Safety
/// `value` must be null or a readable NUL-terminated JSON string for this call.
pub unsafe extern "C" fn wb_record_keys_json(value: *const c_char) -> *mut c_char {
    let events = unsafe { read_c_string(value) }
        .filter(|s| s.len() <= 100_000)
        .and_then(|s| serde_json::from_str::<Vec<crate::recording::RecordedEvent>>(&s).ok());
    let result = events.map_or(
        crate::recording::RecordingResult {
            steps: vec![],
            idle: false,
            error: Some("Invalid recording data"),
        },
        |events| crate::recording::replay_events(&events),
    );
    into_c_string(serde_json::to_string(&result).unwrap_or_default())
}

#[unsafe(no_mangle)]
/// Releases a string allocated by this library.
///
/// # Safety
///
/// `value` must be null or a pointer returned by a WatchBridge function that transfers ownership
/// of a C string. The pointer must not have been freed previously.
pub unsafe extern "C" fn wb_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: this function only accepts pointers returned by `into_c_string`.
        unsafe { drop(CString::from_raw(value)) };
    }
}

#[unsafe(no_mangle)]
/// Releases a byte buffer allocated by this library.
///
/// # Safety
///
/// `value` must be the unchanged `WbBytes` returned by `wb_encode_time`, and it must be released at
/// most once.
pub unsafe extern "C" fn wb_bytes_free(value: WbBytes) {
    if !value.data.is_null() && value.capacity >= value.len {
        // SAFETY: `WbBytes` is created from a Vec with the same pointer, length, and capacity.
        unsafe { drop(Vec::from_raw_parts(value.data, value.len, value.capacity)) };
    }
}

#[unsafe(no_mangle)]
/// Normalizes a watch model supplied as a UTF-8 C string.
///
/// # Safety
///
/// `value` must be null or point to a readable, NUL-terminated string for the duration of the call.
pub unsafe extern "C" fn wb_normalize_model(value: *const c_char) -> *mut c_char {
    let input = unsafe { read_c_string(value) }.unwrap_or_default();
    into_c_string(normalize_model(&input))
}

#[unsafe(no_mangle)]
/// Extracts a normalized model from a Bluetooth display name.
///
/// # Safety
///
/// `value` must be null or point to a readable, NUL-terminated string for the duration of the call.
pub unsafe extern "C" fn wb_model_from_bluetooth_name(value: *const c_char) -> *mut c_char {
    let input = unsafe { read_c_string(value) }.unwrap_or_default();
    into_c_string(model_from_bluetooth_name(&input))
}

#[unsafe(no_mangle)]
/// Converts text to a bounded, printable single line.
///
/// # Safety
///
/// `value` must be null or point to a readable, NUL-terminated string for the duration of the call.
pub unsafe extern "C" fn wb_sanitize_text(
    value: *const c_char,
    maximum_characters: usize,
) -> *mut c_char {
    let input = unsafe { read_c_string(value) }.unwrap_or_default();
    into_c_string(sanitize_single_line(&input, maximum_characters.min(4_096)))
}

#[unsafe(no_mangle)]
/// Validates and normalizes serialized application data.
///
/// # Safety
///
/// `value` must be null or point to a readable, NUL-terminated UTF-8 string for the duration of the
/// call. The returned string must be released with `wb_string_free`.
pub unsafe extern "C" fn wb_validate_app_data_json(value: *const c_char) -> *mut c_char {
    let Some(input) = (unsafe { read_c_string(value) }) else {
        return json_error("The input was not valid UTF-8.");
    };
    if input.len() > MAXIMUM_FFI_STRING_BYTES {
        return json_error("The input exceeded the 10 MB safety limit.");
    }

    match serde_json::from_str::<AppData>(&input) {
        Ok(mut data) => {
            if data.schema_version > crate::model::SCHEMA_VERSION {
                return json_error("The state was created by a newer version.");
            }
            data.trim_for_storage();
            into_json(JsonResult {
                ok: true,
                value: Some(data),
                error: None,
            })
        }
        Err(error) => json_error(&format!("Invalid application state: {error}")),
    }
}

#[unsafe(no_mangle)]
/// Decodes the button gesture reported in a watch packet.
///
/// # Safety
///
/// When `data` is non-null, it must point to at least `len` readable bytes for the duration of the
/// call. `len` must not exceed 65,536.
pub unsafe extern "C" fn wb_decode_button(data: *const u8, len: usize) -> u8 {
    let Some(bytes) = (unsafe { read_bytes(data, len) }) else {
        return event_code(WatchButtonEvent::Unknown);
    };
    event_code(protocol::decode_button(bytes))
}

#[unsafe(no_mangle)]
/// Decodes battery and temperature values from a watch condition packet.
///
/// # Safety
///
/// When `data` is non-null, it must point to at least `len` readable bytes. Both output pointers
/// must point to writable scalar values. All pointers must remain valid for the duration of the call.
pub unsafe extern "C" fn wb_decode_condition(
    data: *const u8,
    len: usize,
    battery_percent: *mut u8,
    temperature_celsius: *mut i16,
) -> bool {
    if battery_percent.is_null() || temperature_celsius.is_null() {
        return false;
    }
    let Some(bytes) = (unsafe { read_bytes(data, len) }) else {
        return false;
    };
    let Some((battery, temperature)) = protocol::decode_condition(bytes) else {
        return false;
    };
    // SAFETY: both output pointers were checked for null and point to caller-owned scalars.
    unsafe {
        *battery_percent = battery;
        *temperature_celsius = temperature;
    }
    true
}

#[unsafe(no_mangle)]
pub extern "C" fn wb_encode_time(unix_seconds: i64, offset_seconds: i32) -> WbBytes {
    let Some(date) = Local.timestamp_opt(unix_seconds, 0).single() else {
        return WbBytes::empty();
    };
    WbBytes::from_vec(protocol::encode_time(
        date + chrono::Duration::seconds(i64::from(offset_seconds.clamp(-300, 300))),
    ))
}

fn event_code(event: WatchButtonEvent) -> u8 {
    match event {
        WatchButtonEvent::Connect => 0,
        WatchButtonEvent::Time => 1,
        WatchButtonEvent::Find => 2,
        WatchButtonEvent::Automatic => 3,
        WatchButtonEvent::Unknown => u8::MAX,
    }
}

unsafe fn read_c_string(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    // SAFETY: the caller contract requires a valid NUL-terminated string.
    let value = unsafe { CStr::from_ptr(value) };
    value.to_str().ok().map(ToOwned::to_owned)
}

unsafe fn read_bytes<'a>(data: *const u8, len: usize) -> Option<&'a [u8]> {
    if data.is_null() || len > 65_536 {
        return None;
    }
    // SAFETY: the caller contract requires `len` readable bytes at `data`.
    Some(unsafe { slice::from_raw_parts(data, len) })
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', ""))
        .unwrap_or_default()
        .into_raw()
}

fn into_json<T: Serialize>(value: JsonResult<T>) -> *mut c_char {
    into_c_string(serde_json::to_string(&value).unwrap_or_else(|_| {
        r#"{"ok":false,"value":null,"error":"Could not serialize the result."}"#.to_owned()
    }))
}

fn json_error(message: &str) -> *mut c_char {
    into_json(JsonResult::<AppData> {
        ok: false,
        value: None,
        error: Some(sanitize_single_line(message, 512)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_protocol_functions_match_the_safe_api() {
        let mut packet = [0_u8; 19];
        packet[0] = protocol::code::BLE_FEATURES;
        packet[8] = 2;
        // SAFETY: packet is valid for its complete length.
        assert_eq!(
            unsafe { wb_decode_button(packet.as_ptr(), packet.len()) },
            2
        );

        let encoded = wb_encode_time(1_788_543_600, 0);
        assert_eq!(encoded.len, 11);
        // SAFETY: the buffer came directly from `wb_encode_time`.
        unsafe { wb_bytes_free(encoded) };
    }

    #[test]
    fn malformed_json_returns_an_error_envelope() {
        let input = CString::new("not json").unwrap();
        // SAFETY: input is a valid C string and the returned pointer is freed below.
        let output = unsafe { wb_validate_app_data_json(input.as_ptr()) };
        // SAFETY: output is a valid C string owned by this library.
        let decoded = unsafe { CStr::from_ptr(output) }
            .to_string_lossy()
            .into_owned();
        // SAFETY: output was allocated by this library.
        unsafe { wb_string_free(output) };
        assert!(decoded.contains(r#""ok":false"#));
    }
}
