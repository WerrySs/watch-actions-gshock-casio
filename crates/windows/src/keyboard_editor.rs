//! Explicit editor-local recording. No global hooks, text capture or background listeners.
use crate::{
    MainWindow, RecordedKeyRow, editing_layer, event_for_code, state::SharedState, ui_model,
};
use slint::{ComponentHandle as _, Timer};
use std::{
    cell::RefCell,
    rc::Rc,
    sync::Arc,
    time::{Duration, Instant},
};
use watchbridge_core::{
    keyboard::{KEYS, KeyboardShortcut, KeyboardStep},
    model::{ActionKind, WatchAction, WatchButtonEvent},
    modes::ActionLayer,
    recording::KeyRecorder,
};

#[derive(Default)]
struct Editor {
    draft: KeyboardShortcut,
    recorder: Option<KeyRecorder>,
    started: Option<Instant>,
    generation: u64,
}
impl Editor {
    fn display(&self, ui: &MainWindow) {
        let steps = self
            .recorder
            .as_ref()
            .map(|r| r.steps().to_vec())
            .unwrap_or_else(|| self.draft.steps().unwrap_or_default());
        ui.set_recorded_keys(ui_model(
            steps
                .iter()
                .enumerate()
                .map(|(index, step)| RecordedKeyRow {
                    title: step.summary().into(),
                    detail: if index == 0 {
                        "1 · Start".into()
                    } else {
                        format!("{} · +{} ms", index + 1, step.delay_ms).into()
                    },
                })
                .collect::<Vec<_>>(),
        ));
        ui.set_keyboard_valid(self.recorder.is_none() && self.draft.is_valid());
        ui.set_keyboard_recording(self.recorder.is_some());
    }
    fn stop(&mut self, ui: &MainWindow, state: &SharedState, message: &str) {
        if self.recorder.take().is_some() {
            state.finish_action("Keyboard recording ended; no input was sent".into());
        }
        self.started = None;
        self.generation = self.generation.wrapping_add(1);
        ui.set_recording_message(message.into());
        self.display(ui);
    }
}

pub fn install(ui: &MainWindow, state: Arc<SharedState>) {
    let editor = Rc::new(RefCell::new(Editor::default()));
    ui.set_manual_key_labels(ui_model(
        KEYS.iter().map(|key| key.label.into()).collect::<Vec<_>>(),
    ));
    ui.on_edit_keyboard({
        let weak = ui.as_weak();
        let state = state.clone();
        let editor = editor.clone();
        move |code| {
            let (Some(ui), Some(event)) = (weak.upgrade(), event_for_code(code.as_str())) else {
                return;
            };
            let layer = editing_layer(&state, event);
            let mut editor = editor.borrow_mut();
            editor.stop(
                &ui,
                &state,
                "Click Record, press your shortcut, then click Stop.",
            );
            editor.draft = state
                .data
                .read()
                .actions
                .action_in_layer(event, layer)
                .keyboard
                .unwrap_or_default();
            ui.set_keyboard_layer(layer.id() as i32);
            ui.set_keyboard_event(code);
            editor.display(&ui);
        }
    });
    ui.on_toggle_recording({
        let weak = ui.as_weak(); let state = state.clone(); let editor = editor.clone();
        move || {
            let Some(ui) = weak.upgrade() else { return };
            let mut e = editor.borrow_mut();
            if let Some(recorder) = &e.recorder {
                if !recorder.is_idle() || recorder.steps().is_empty() { ui.set_recording_message("Release every key and record at least one tap before stopping.".into()); return; }
                e.draft = KeyboardShortcut::recorded(recorder.steps().to_vec());
                e.stop(&ui, &state, "Recorded. Review the steps, then save.");
            } else {
                #[cfg(target_os = "windows")]
                if [0x10, 0x11, 0x12, 0x5B, 0x5C].iter().any(|key| unsafe { windows_sys::Win32::UI::Input::KeyboardAndMouse::GetAsyncKeyState(*key) } < 0) {
                    ui.set_recording_message("Release modifier keys before recording.".into()); return;
                }
                if !state.begin_action() { ui.set_recording_message("Wait for the current action to finish before recording.".into()); return; }
                e.recorder = Some(KeyRecorder::default()); e.started = Some(Instant::now());
                e.generation = e.generation.wrapping_add(1);
                let generation = e.generation;
                ui.set_recording_message("Recording… press and release keys. Esc cancels. Never enter passwords.".into()); e.display(&ui);
                let weak = ui.as_weak(); let state = state.clone(); let editor = editor.clone();
                Timer::single_shot(Duration::from_secs(30), move || {
                    let Some(ui) = weak.upgrade() else { return };
                    let mut e = editor.borrow_mut();
                    if e.generation == generation { e.stop(&ui, &state, "Recording cancelled after 30 seconds. Keep shortcuts short."); }
                });
            }
        }
    });
    ui.on_cancel_keyboard({
        let weak = ui.as_weak();
        let state = state.clone();
        let editor = editor.clone();
        move || {
            if let Some(ui) = weak.upgrade() {
                editor
                    .borrow_mut()
                    .stop(&ui, &state, "Recording cancelled.");
                ui.set_keyboard_event("".into());
            }
        }
    });
    ui.on_keyboard_preset({
        let weak = ui.as_weak();
        let editor = editor.clone();
        move |key| {
            let Some(ui) = weak.upgrade() else { return };
            let mut e = editor.borrow_mut();
            if e.recorder.is_some() || !["meta", "right"].contains(&key.as_str()) {
                return;
            }
            e.draft = KeyboardShortcut::recorded(vec![
                KeyboardStep {
                    key: key.to_string(),
                    modifiers: 0,
                    delay_ms: 0,
                },
                KeyboardStep {
                    key: key.to_string(),
                    modifiers: 0,
                    delay_ms: 140,
                },
            ]);
            e.display(&ui);
        }
    });
    ui.on_undo_keyboard({
        let weak = ui.as_weak();
        let editor = editor.clone();
        move || {
            if let Some(ui) = weak.upgrade() {
                let mut e = editor.borrow_mut();
                if e.recorder.is_some() {
                    return;
                }
                let mut steps = e.draft.steps().unwrap_or_default();
                steps.pop();
                e.draft = KeyboardShortcut::recorded(steps);
                e.display(&ui);
            }
        }
    });
    ui.on_add_manual_key({
        let weak = ui.as_weak();
        let editor = editor.clone();
        move || {
            let Some(ui) = weak.upgrade() else { return };
            let mut e = editor.borrow_mut();
            if e.recorder.is_some() {
                return;
            }
            let Some(key) = KEYS.get(ui.get_manual_key_index() as usize) else {
                return;
            };
            let shortcut = KeyboardShortcut {
                key: key.id.into(),
                control: ui.get_keyboard_control(),
                alt: ui.get_keyboard_alt(),
                shift: ui.get_keyboard_shift(),
                meta: ui.get_keyboard_meta(),
                repetitions: ui.get_keyboard_repetitions().try_into().unwrap_or(0),
                sequence: None,
            };
            let Some(added) = shortcut.steps() else {
                ui.set_recording_message(
                    "Choose valid modifiers; do not add a modifier to itself.".into(),
                );
                return;
            };
            let mut steps = e.draft.steps().unwrap_or_default();
            for mut step in added {
                if !steps.is_empty() && step.delay_ms == 0 {
                    step.delay_ms = 100;
                }
                steps.push(step);
            }
            let draft = KeyboardShortcut::recorded(steps);
            if !draft.is_valid() {
                ui.set_recording_message(
                    "A recording can contain up to 32 steps and 30 seconds of pauses.".into(),
                );
                return;
            }
            e.draft = draft;
            e.display(&ui);
        }
    });
    ui.on_save_keyboard({
        let weak = ui.as_weak();
        let state = state.clone();
        let editor = editor.clone();
        move || {
            let Some(ui) = weak.upgrade() else { return };
            let e = editor.borrow();
            if e.recorder.is_some() || !e.draft.is_valid() || !state.can_mutate() {
                return;
            }
            let Some(event) = event_for_code(ui.get_keyboard_event().as_str()) else {
                return;
            };
            let layer = if event == WatchButtonEvent::Automatic {
                ActionLayer::Normal
            } else {
                ActionLayer::from_id(ui.get_keyboard_layer().try_into().unwrap_or(0))
            };
            let mut data = state.data.write();
            let Some(actions) = data.actions.actions_mut(layer) else {
                return;
            };
            actions.insert(
                event,
                WatchAction {
                    kind: ActionKind::Keyboard,
                    value: String::new(),
                    keyboard: Some(e.draft.clone()),
                },
            );
            drop(data);
            state.save();
            ui.set_keyboard_event("".into());
        }
    });
    install_local_events(ui, state, editor);
}

fn install_local_events(ui: &MainWindow, state: Arc<SharedState>, editor: Rc<RefCell<Editor>>) {
    use slint::winit_030::{
        EventResult, WinitWindowAccessor as _,
        winit::event::{ElementState, WindowEvent},
    };
    let weak = ui.as_weak();
    ui.window().on_winit_window_event(move |_, event| {
        let Some(ui) = weak.upgrade() else { return EventResult::Propagate };
        let mut e = editor.borrow_mut();
        if e.recorder.is_none() { return EventResult::Propagate; }
        match event {
            WindowEvent::Focused(false) | WindowEvent::CloseRequested => {
                e.stop(&ui, &state, "Recording cancelled because the editor lost focus. Use presets for system-reserved keys.");
            }
            WindowEvent::KeyboardInput { event, is_synthetic, .. } => {
                if *is_synthetic || event.repeat { return EventResult::PreventDefault; }
                let key = key_for_physical(event.physical_key);
                let Some(key) = key else { e.stop(&ui, &state, "Unsupported key. Record again using standard keys and modifiers."); return EventResult::PreventDefault };
                let down = event.state == ElementState::Pressed;
                if key.id == "escape" && down { e.stop(&ui, &state, "Recording cancelled. Your saved shortcut is unchanged."); return EventResult::PreventDefault; }
                let time = e.started.map_or(0, |start| start.elapsed().as_millis() as u64);
                if let Err(error) = e.recorder.as_mut().unwrap().event(key.id, down, time) {
                    e.stop(&ui, &state, &format!("{error}. Record again."));
                } else { e.display(&ui); }
                return EventResult::PreventDefault;
            }
            _ => {}
        }
        EventResult::Propagate
    });
}

fn key_for_physical(
    physical: slint::winit_030::winit::keyboard::PhysicalKey,
) -> Option<&'static watchbridge_core::keyboard::KeyboardKey> {
    use slint::winit_030::winit::platform::scancode::PhysicalKeyExtScancode as _;
    let scan = physical.to_scancode()?;
    KEYS.iter().find(|key| {
        #[cfg(target_os = "macos")]
        let code = u32::from(key.mac_code);
        #[cfg(not(target_os = "macos"))]
        let code = u32::from(key.windows_scan) | if key.extended { 0xE000 } else { 0 };
        code == scan
    })
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::*;
    use slint::winit_030::winit::keyboard::{KeyCode, PhysicalKey};
    #[test]
    fn local_physical_events_preserve_modifier_sides_and_arrows() {
        for (key, id) in [
            (KeyCode::SuperLeft, "meta"),
            (KeyCode::SuperRight, "right_meta"),
            (KeyCode::ControlRight, "right_control"),
            (KeyCode::AltRight, "right_alt"),
            (KeyCode::ArrowRight, "right"),
            (KeyCode::KeyC, "c"),
        ] {
            assert_eq!(key_for_physical(PhysicalKey::Code(key)).unwrap().id, id);
        }
        assert!(key_for_physical(PhysicalKey::Code(KeyCode::CapsLock)).is_none());
    }
}
