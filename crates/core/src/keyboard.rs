//! Bounded physical-key shortcuts. Labels use US reference positions; the OS layout
//! determines printable characters. Recording consumes explicit, window-local key events only.
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
    key("control", "Ctrl", 6, 59, 29, false),
    key("alt", "Alt", 6, 58, 56, false),
    key("shift", "Shift", 6, 56, 42, false),
    key("meta", "Win", 6, 55, 91, true),
    key("right_control", "Right Ctrl", 6, 62, 29, true),
    key("right_alt", "Right Alt", 6, 61, 56, true),
    key("right_shift", "Right Shift", 6, 60, 54, false),
    key("right_meta", "Right Win", 6, 54, 92, true),
];

impl KeyboardKey {
    pub fn modifier(&self) -> u8 {
        match self.id {
            "control" | "right_control" => 1,
            "alt" | "right_alt" => 2,
            "shift" | "right_shift" => 4,
            "meta" | "right_meta" => 8,
            _ => 0,
        }
    }
}

pub const MAX_RECORDED_STEPS: usize = 32;
pub const MAX_RECORDING_MS: u64 = 30_000;

/// One complete, balanced tap/chord. Delay precedes the tap, never its release.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct KeyboardStep {
    pub key: String,
    pub modifiers: u8,
    pub delay_ms: u16,
}

impl KeyboardStep {
    pub fn definition(&self) -> Option<&'static KeyboardKey> {
        let key = KEYS.iter().find(|k| k.id == self.key)?;
        (self.modifiers <= 15 && self.modifiers & key.modifier() == 0 && self.delay_ms <= 2000)
            .then_some(key)
    }
    pub fn summary(&self) -> String {
        let Some(key) = self.definition() else {
            return "Invalid key".into();
        };
        let mut labels = Vec::new();
        for (bit, label) in [(1, "Ctrl"), (2, "Alt"), (4, "Shift"), (8, "Win")] {
            if self.modifiers & bit != 0 {
                labels.push(label);
            }
        }
        labels.push(key.label);
        labels.join(" + ")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct KeyboardShortcut {
    pub key: String,
    pub control: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
    pub repetitions: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sequence: Option<Vec<KeyboardStep>>,
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
            sequence: None,
        }
    }
}

impl KeyboardShortcut {
    pub fn definition(&self) -> Option<&'static KeyboardKey> {
        if self.sequence.is_some() || !(1..=10).contains(&self.repetitions) {
            return None;
        }
        self.step(0).definition()
    }
    fn step(&self, delay_ms: u16) -> KeyboardStep {
        KeyboardStep {
            key: self.key.clone(),
            modifiers: u8::from(self.control)
                | (u8::from(self.alt) << 1)
                | (u8::from(self.shift) << 2)
                | (u8::from(self.meta) << 3),
            delay_ms,
        }
    }
    pub fn recorded(steps: Vec<KeyboardStep>) -> Self {
        // Old clients reject this unknown key instead of silently replaying a fallback arrow.
        Self {
            key: "recorded_sequence".into(),
            sequence: Some(steps),
            ..Default::default()
        }
    }
    pub fn steps(&self) -> Option<Vec<KeyboardStep>> {
        if let Some(steps) = &self.sequence {
            if self.key != "recorded_sequence"
                || self.repetitions != 1
                || self.control
                || self.alt
                || self.shift
                || self.meta
                || steps.is_empty()
                || steps.len() > MAX_RECORDED_STEPS
                || steps[0].delay_ms != 0
                || steps.iter().skip(1).any(|s| s.delay_ms < 40)
                || steps.iter().any(|s| s.definition().is_none())
                || steps.iter().map(|s| u64::from(s.delay_ms)).sum::<u64>() > MAX_RECORDING_MS
            {
                return None;
            }
            return Some(steps.clone());
        }
        self.definition()?;
        Some(
            (0..self.repetitions)
                .map(|i| self.step(if i == 0 { 0 } else { 100 }))
                .collect(),
        )
    }
    pub fn is_valid(&self) -> bool {
        self.steps().is_some()
    }
    pub fn recording_summary(&self) -> String {
        self.steps().map_or_else(
            || "Record a shortcut".into(),
            |steps| {
                steps
                    .iter()
                    .map(KeyboardStep::summary)
                    .collect::<Vec<_>>()
                    .join(" → ")
            },
        )
    }
    pub fn summary(&self) -> String {
        if self.sequence.is_some() {
            return self.recording_summary();
        }
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
    fn recordings_validate_every_step_and_round_trip() {
        let valid = KeyboardShortcut::recorded(vec![
            KeyboardStep {
                key: "meta".into(),
                modifiers: 0,
                delay_ms: 0,
            },
            KeyboardStep {
                key: "meta".into(),
                modifiers: 0,
                delay_ms: 140,
            },
        ]);
        assert!(valid.is_valid());
        assert!(valid.definition().is_none());
        assert_eq!(valid.summary(), "Win → Win");
        assert_eq!(
            serde_json::from_slice::<KeyboardShortcut>(&serde_json::to_vec(&valid).unwrap())
                .unwrap(),
            valid
        );
        for steps in [
            vec![],
            vec![KeyboardStep {
                key: "meta".into(),
                modifiers: 8,
                delay_ms: 0,
            }],
            vec![KeyboardStep {
                key: "meta".into(),
                modifiers: 0,
                delay_ms: 1,
            }],
            vec![
                KeyboardStep {
                    key: "meta".into(),
                    modifiers: 0,
                    delay_ms: 0
                };
                33
            ],
        ] {
            assert!(!KeyboardShortcut::recorded(steps).is_valid());
        }
        let mut malformed = valid;
        malformed.repetitions = 2;
        assert!(!malformed.is_valid());
    }
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
