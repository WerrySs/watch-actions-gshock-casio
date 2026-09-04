use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{DateTime, Utc};
use parking_lot::RwLock;
use watchbridge_core::model::{AppData, ConnectionPhase};

#[derive(Debug, Clone)]
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub struct RuntimeStatus {
    pub phase: ConnectionPhase,
    pub message: String,
    pub connected_watch_id: Option<String>,
    pub is_scanning: bool,
    pub trace: VecDeque<String>,
    pub last_action_result: Option<String>,
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
}

impl SharedState {
    pub fn load(state_path: PathBuf) -> Arc<Self> {
        let (data, load_error) = match watchbridge_core::storage::load(&state_path) {
            Ok(data) => (data, None),
            Err(error) => (AppData::default(), Some(error.to_string())),
        };
        let shared = Arc::new(Self {
            data: RwLock::new(data),
            runtime: RwLock::new(RuntimeStatus::default()),
            state_path,
            revision: AtomicU64::new(0),
            demo: false,
        });
        if let Some(error) = load_error {
            let mut runtime = shared.runtime.write();
            runtime.set(ConnectionPhase::Error, "Local data could not be loaded");
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
        })
    }

    pub fn save(&self) {
        if self.demo {
            return;
        }
        let snapshot = self.data.read().clone();
        if let Err(error) = watchbridge_core::storage::save(&self.state_path, &snapshot) {
            let mut runtime = self.runtime.write();
            runtime.set(ConnectionPhase::Error, "Local data could not be saved");
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
}
