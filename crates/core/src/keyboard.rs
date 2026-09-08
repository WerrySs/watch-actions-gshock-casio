//! Bounded physical-key shortcuts. Labels use US reference positions; the OS layout
//! determines printable characters. No text recording, scripts, or global key hooks.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyboardKey {
    pub id: &'static str,
    pub label: &'static str,
    pub row: u8,
    pub mac_code: u16,
    pub windows_scan: u16,
    pub extended: bool,
}

const fn key(
    id: &'static str,
    label: &'static str,
    row: u8,
    mac_code: u16,
    windows_scan: u16,
    extended: bool,
) -> KeyboardKey {
    KeyboardKey {
        id,
        label,
        row,
        mac_code,
        windows_scan,
        extended,
    }
}

// ID, display label, visual row, macOS virtual key, Windows scan code, extended flag.
pub const KEYS: &[KeyboardKey] = &[
    key("escape", "Esc", 0, 53, 1, false),
    key("f1", "F1", 0, 122, 59, false),
    key("f2", "F2", 0, 120, 60, false),
    key("f3", "F3", 0, 99, 61, false),
    key("f4", "F4", 0, 118, 62, false),
    key("f5", "F5", 0, 96, 63, false),
    key("f6", "F6", 0, 97, 64, false),
    key("f7", "F7", 0, 98, 65, false),
    key("f8", "F8", 0, 100, 66, false),
    key("f9", "F9", 0, 101, 67, false),
    key("f10", "F10", 0, 109, 68, false),
    key("f11", "F11", 0, 103, 87, false),
    key("f12", "F12", 0, 111, 88, false),
    key("backtick", "`", 1, 50, 41, false),
    key("digit1", "1", 1, 18, 2, false),
    key("digit2", "2", 1, 19, 3, false),
    key("digit3", "3", 1, 20, 4, false),
    key("digit4", "4", 1, 21, 5, false),
    key("digit5", "5", 1, 23, 6, false),
    key("digit6", "6", 1, 22, 7, false),
    key("digit7", "7", 1, 26, 8, false),
    key("digit8", "8", 1, 28, 9, false),
    key("digit9", "9", 1, 25, 10, false),
    key("digit0", "0", 1, 29, 11, false),
    key("minus", "−", 1, 27, 12, false),
    key("equal", "=", 1, 24, 13, false),
    key("backspace", "⌫", 1, 51, 14, false),
    key("tab", "Tab", 2, 48, 15, false),
    key("q", "Q", 2, 12, 16, false),
    key("w", "W", 2, 13, 17, false),
    key("e", "E", 2, 14, 18, false),
    key("r", "R", 2, 15, 19, false),
    key("t", "T", 2, 17, 20, false),
    key("y", "Y", 2, 16, 21, false),
    key("u", "U", 2, 32, 22, false),
    key("i", "I", 2, 34, 23, false),
    key("o", "O", 2, 31, 24, false),
    key("p", "P", 2, 35, 25, false),
    key("left_bracket", "[", 2, 33, 26, false),
    key("right_bracket", "]", 2, 30, 27, false),
    key("backslash", "\\", 2, 42, 43, false),
    key("a", "A", 3, 0, 30, false),
    key("s", "S", 3, 1, 31, false),
    key("d", "D", 3, 2, 32, false),
    key("f", "F", 3, 3, 33, false),
    key("g", "G", 3, 5, 34, false),
    key("h", "H", 3, 4, 35, false),
    key("j", "J", 3, 38, 36, false),
    key("k", "K", 3, 40, 37, false),
    key("l", "L", 3, 37, 38, false),
    key("semicolon", ";", 3, 41, 39, false),
    key("quote", "'", 3, 39, 40, false),
    key("enter", "Enter", 3, 36, 28, false),
    key("z", "Z", 4, 6, 44, false),
    key("x", "X", 4, 7, 45, false),
    key("c", "C", 4, 8, 46, false),
    key("v", "V", 4, 9, 47, false),
    key("b", "B", 4, 11, 48, false),
    key("n", "N", 4, 45, 49, false),
    key("m", "M", 4, 46, 50, false),
    key("comma", ",", 4, 43, 51, false),
    key("period", ".", 4, 47, 52, false),
    key("slash", "/", 4, 44, 53, false),
    key("space", "Space", 4, 49, 57, false),
    key("home", "Home", 5, 115, 71, true),
    key("end", "End", 5, 119, 79, true),
    key("page_up", "PgUp", 5, 116, 73, true),
    key("page_down", "PgDn", 5, 121, 81, true),
    key("delete", "Del", 5, 117, 83, true),
    key("left", "←", 5, 123, 75, true),
    key("down", "↓", 5, 125, 80, true),
    key("up", "↑", 5, 126, 72, true),
    key("right", "→", 5, 124, 77, true),
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct KeyboardShortcut {
    pub key: String,
    pub control: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
    pub repetitions: u8,
}

impl Default for KeyboardShortcut {
    fn default() -> Self {
        Self {
            key: "right".to_owned(),
            control: false,
            alt: false,
            shift: false,
            meta: false,
            repetitions: 1,
        }
    }
}

impl KeyboardShortcut {
    pub fn definition(&self) -> Option<&'static KeyboardKey> {
        (1..=10)
            .contains(&self.repetitions)
            .then(|| KEYS.iter().find(|key| key.id == self.key))
            .flatten()
    }
    pub fn summary(&self) -> String {
        let Some(key) = self.definition() else {
            return "Configure keyboard shortcut".to_owned();
        };
        let mut labels = Vec::new();
        if self.control {
            labels.push("Ctrl");
        }
        if self.alt {
            labels.push("Alt");
        }
        if self.shift {
            labels.push("Shift");
        }
        if self.meta {
            labels.push("Win");
        }
        labels.push(key.label);
        format!("{} ×{}", labels.join(" + "), self.repetitions)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn catalog_has_unique_codes_and_ids() {
        use std::collections::BTreeSet;
        for values in [
            KEYS.iter().map(|k| k.id.to_owned()).collect::<Vec<_>>(),
            KEYS.iter().map(|k| k.mac_code.to_string()).collect(),
            KEYS.iter()
                .map(|k| format!("{}:{}", k.windows_scan, k.extended))
                .collect(),
        ] {
            assert_eq!(values.iter().collect::<BTreeSet<_>>().len(), KEYS.len());
        }
    }
    #[test]
    fn invalid_keys_and_repeat_counts_fail_closed() {
        let mut shortcut = KeyboardShortcut::default();
        assert_eq!(shortcut.summary(), "→ ×1");
        for count in [0, 11, 255] {
            shortcut.repetitions = count;
            assert!(shortcut.definition().is_none());
        }
        shortcut.repetitions = 2;
        shortcut.key = "shell:command".to_owned();
        assert!(shortcut.definition().is_none());
    }
}
