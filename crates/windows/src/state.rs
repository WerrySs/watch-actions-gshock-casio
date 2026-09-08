use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use chrono::{DateTime, Utc};
use parking_lot::{Mutex, RwLock};
use watchbridge_core::model::{AppData, ConnectionPhase};
use watchbridge_core::modes::{ActionLayer, ActionModes};

#[derive(Debug, Clone)]
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub struct RuntimeStatus {
    pub phase: ConnectionPhase,
    pub message: String,
    pub connected_watch_id: Option<String>,
    pub is_scanning: bool,
    pub trace: VecDeque<String>,
    pub last_action_result: Option<String>,
    pub action_modes: ActionModes,
    pub editing_layer: ActionLayer,
    pub last_update: DateTime<Utc>,
}

impl Default for RuntimeStatus {
    fn default() -> Self {
        Self {
            phase: ConnectionPhase::Starting,
            message: "Starting Bluetooth".to_owned(),
            connected_watch_id: None,
            is_scanning: false,
            trace: VecDeque::new(),
            last_action_result: None,
            action_modes: ActionModes::default(),
            editing_layer: ActionLayer::Normal,
            last_update: Utc::now(),
        }
    }
}

impl RuntimeStatus {
    pub fn set(&mut self, phase: ConnectionPhase, message: impl Into<String>) {
        self.phase = phase;
        self.message = message.into();
        self.last_update = Utc::now();
    }

    pub fn push_trace(&mut self, line: impl Into<String>) {
        self.trace.push_back(line.into());
        while self.trace.len() > 400 {
            self.trace.pop_front();
        }
        self.last_update = Utc::now();
    }
}

#[derive(Debug)]
pub struct SharedState {
    pub data: RwLock<AppData>,
    pub runtime: RwLock<RuntimeStatus>,
    state_path: PathBuf,
    revision: AtomicU64,
    demo: bool,
    writable: AtomicBool,
    saving: Mutex<()>,
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    action_running: AtomicBool,
}

impl SharedState {
    pub fn load(state_path: PathBuf) -> Arc<Self> {
        let (data, load_error) = match watchbridge_core::storage::load(&state_path) {
            Ok(data) => (data, None),
            Err(error) => (AppData::default(), Some(error.to_string())),
        };
        let writable = load_error.is_none();
        let shared = Arc::new(Self {
            data: RwLock::new(data),
            runtime: RwLock::new(RuntimeStatus::default()),
            state_path,
            revision: AtomicU64::new(0),
            demo: false,
            writable: AtomicBool::new(writable),
            saving: Mutex::new(()),
            action_running: AtomicBool::new(false),
        });
        if let Some(error) = load_error {
            let mut runtime = shared.runtime.write();
            runtime.set(ConnectionPhase::Error, "Local data is protected: restore a valid backup and restart. Bluetooth and saves are paused.");
            runtime.push_trace(error);
        }
        shared
    }

    pub fn demo() -> Arc<Self> {
        let mut runtime = RuntimeStatus::default();
        runtime.set(ConnectionPhase::Waiting, "Demo mode · saved watch state");
        Arc::new(Self {
            data: RwLock::new(AppData::demo()),
            runtime: RwLock::new(runtime),
            state_path: PathBuf::new(),
            revision: AtomicU64::new(0),
            demo: true,
            writable: AtomicBool::new(true),
            saving: Mutex::new(()),
            action_running: AtomicBool::new(false),
        })
    }

    pub fn save(&self) {
        if !self.can_mutate() {
            return;
        }
        let _saving = self.saving.lock();
        if !self.can_mutate() {
            return;
        }
        self.revision.fetch_add(1, Ordering::Relaxed);
        if self.demo {
            return;
        }
        let snapshot = self.data.read().clone();
        if let Err(error) = watchbridge_core::storage::save(&self.state_path, &snapshot) {
            self.writable.store(false, Ordering::Relaxed);
            let mut runtime = self.runtime.write();
            runtime.set(
                ConnectionPhase::Error,
                "Saving failed. Writes and actions are paused; check local storage and restart.",
            );
            runtime.push_trace(error.to_string());
        } else {
            self.revision.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn trace(&self, line: impl Into<String>) {
        let timestamp = chrono::Local::now().format("%H:%M:%S");
        self.runtime
            .write()
            .push_trace(format!("{timestamp}  {}", line.into()));
    }

    pub fn revision(&self) -> u64 {
        self.revision.load(Ordering::Relaxed)
    }

    pub fn can_mutate(&self) -> bool {
        self.writable.load(Ordering::Relaxed)
    }

    pub fn begin_action(&self) -> bool {
        self.can_mutate()
            && self
                .action_running
                .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
    }

    pub fn finish_action(&self, summary: String) {
        let mut runtime = self.runtime.write();
        runtime.last_action_result = Some(summary);
        runtime.last_update = Utc::now();
        self.action_running.store(false, Ordering::SeqCst);
        self.revision.fetch_add(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recording_reserves_the_same_gate_as_watch_and_manual_actions() {
        let state = SharedState::demo();
        assert!(state.begin_action());
        assert!(!state.begin_action());
        state.finish_action("Recording ended without input".into());
        assert!(state.begin_action());
        state.finish_action("Test ended".into());
    }
    #[test]
    fn failed_loads_are_not_overwritten() {
        let folder = tempfile::tempdir().unwrap();
        let path = folder.path().join("state.json");
        for bytes in [
            b"not JSON".as_slice(),
            b"{\"schema_version\":999}".as_slice(),
        ] {
            std::fs::write(&path, bytes).unwrap();
            let state = SharedState::load(path.clone());
            assert!(!state.can_mutate());
            state.save();
            assert_eq!(std::fs::read(&path).unwrap(), bytes);
        }
    }
}
