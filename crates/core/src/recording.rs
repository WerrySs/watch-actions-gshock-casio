//! Pure bounded recorder. Never opens a keyboard device, installs a hook or reads text.
use crate::keyboard::{KEYS, KeyboardStep, MAX_RECORDED_STEPS, MAX_RECORDING_MS};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Deserialize)]
pub struct RecordedEvent {
    pub key: String,
    pub down: bool,
    pub time_ms: u64,
}
#[derive(Serialize)]
pub struct RecordingResult {
    pub steps: Vec<KeyboardStep>,
    pub idle: bool,
    pub error: Option<&'static str>,
}
pub fn replay_events(events: &[RecordedEvent]) -> RecordingResult {
    let mut recorder = KeyRecorder::default();
    let mut error = None;
    if events.len() > 512 {
        error = Some("Recording contains too many key transitions");
    } else {
        let mut last = 0;
        for event in events {
            if event.time_ms < last {
                error = Some("Recording timestamps are invalid");
                break;
            }
            last = event.time_ms;
            if let Err(message) = recorder.event(&event.key, event.down, event.time_ms) {
                error = Some(message);
                break;
            }
        }
    }
    RecordingResult {
        steps: recorder.steps().to_vec(),
        idle: recorder.is_idle(),
        error,
    }
}

#[derive(Default)]
pub struct KeyRecorder {
    held: BTreeMap<String, bool>,
    pending: Option<KeyboardStep>,
    steps: Vec<KeyboardStep>,
    started: Option<u64>,
    last_release: Option<u64>,
    modifier_start: Option<u64>,
}

impl KeyRecorder {
    pub fn steps(&self) -> &[KeyboardStep] {
        &self.steps
    }
    pub fn is_idle(&self) -> bool {
        self.held.is_empty() && self.pending.is_none()
    }
    fn delay(&self, time: u64) -> u16 {
        self.last_release
            .map_or(0, |last| time.saturating_sub(last).clamp(40, 2000) as u16)
    }
    fn modifiers(&self) -> u8 {
        self.held
            .keys()
            .filter_map(|id| KEYS.iter().find(|key| key.id == id))
            .fold(0, |bits, key| bits | key.modifier())
    }
    pub fn event(&mut self, id: &str, down: bool, time_ms: u64) -> Result<(), &'static str> {
        let key = KEYS
            .iter()
            .find(|key| key.id == id)
            .ok_or("This key cannot be recorded")?;
        let started = *self.started.get_or_insert(time_ms);
        if time_ms.saturating_sub(started) > MAX_RECORDING_MS {
            return Err("Recording reached 30 seconds");
        }
        if down {
            if self.held.contains_key(id) {
                return Ok(());
            } // OS auto-repeat is not another tap.
            if self.steps.len() >= MAX_RECORDED_STEPS {
                return Err("Recording reached 32 steps");
            }
            if key.modifier() != 0 {
                if self.modifiers() & key.modifier() != 0 {
                    return Err("Use one side of each modifier at a time");
                }
                if self.pending.is_some() {
                    return Err("Press modifiers before the main key");
                }
                if self.held.is_empty() {
                    self.modifier_start = Some(time_ms);
                }
            } else {
                if self.pending.is_some() {
                    return Err("Release the main key before pressing the next one");
                }
                self.pending = Some(KeyboardStep {
                    key: id.into(),
                    modifiers: self.modifiers(),
                    delay_ms: self.delay(time_ms),
                });
                for used in self.held.values_mut() {
                    *used = true;
                }
            }
            self.held.insert(id.into(), false);
        } else {
            let Some(used) = self.held.get(id).copied() else {
                return Ok(());
            };
            if key.modifier() == 0 {
                if let Some(step) = self.pending.take() {
                    self.steps.push(step);
                    self.last_release = Some(time_ms);
                }
            } else if !used {
                let step = KeyboardStep {
                    key: id.into(),
                    modifiers: self.modifiers() & !key.modifier(),
                    delay_ms: self.delay(self.modifier_start.unwrap_or(time_ms)),
                };
                self.steps.push(step);
                self.last_release = Some(time_ms);
                for used in self.held.values_mut() {
                    *used = true;
                }
            }
            self.held.remove(id);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn double_command_is_two_balanced_modifier_taps() {
        let mut r = KeyRecorder::default();
        for (down, time) in [(true, 0), (false, 40), (true, 180), (false, 220)] {
            r.event("meta", down, time).unwrap();
        }
        assert_eq!(
            r.steps(),
            [
                KeyboardStep {
                    key: "meta".into(),
                    modifiers: 0,
                    delay_ms: 0
                },
                KeyboardStep {
                    key: "meta".into(),
                    modifiers: 0,
                    delay_ms: 140
                }
            ]
        );
        assert!(r.is_idle());
    }
    #[test]
    fn chord_does_not_append_a_phantom_modifier_tap() {
        let mut r = KeyRecorder::default();
        for (key, down) in [
            ("meta", true),
            ("c", true),
            ("c", true),
            ("c", false),
            ("meta", false),
        ] {
            r.event(key, down, 0).unwrap();
        }
        assert_eq!(
            r.steps(),
            [KeyboardStep {
                key: "c".into(),
                modifiers: 8,
                delay_ms: 0
            }]
        );
    }
    #[test]
    fn cancellation_can_drop_incomplete_input_and_unsupported_keys_fail() {
        let mut r = KeyRecorder::default();
        r.event("right", true, 0).unwrap();
        assert!(!r.is_idle());
        assert!(r.steps().is_empty());
        assert!(r.event("left", true, 1).is_err());
        assert!(r.event("caps_lock", true, 2).is_err());
    }
    #[test]
    fn recording_is_bounded_and_auto_repeat_is_ignored() {
        let mut r = KeyRecorder::default();
        for i in 0..32 {
            r.event("right", true, i * 100).unwrap();
            r.event("right", false, i * 100 + 40).unwrap();
        }
        assert!(r.event("right", true, 4000).is_err());
        let mut r = KeyRecorder::default();
        r.event("meta", true, 0).unwrap();
        assert!(r.event("meta", false, 30_001).is_err());
    }
}
