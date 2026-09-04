use std::collections::{BTreeMap, BTreeSet};

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const SCHEMA_VERSION: u32 = 1;
const MAXIMUM_WATCHES: usize = 100;
const MAXIMUM_PENDING_CHANGES: usize = 32;
const MAXIMUM_HISTORY_RECORDS: usize = 300;
pub const KNOWN_MODELS: &[(&str, &str)] = &[
    ("GW-B5600", "GW-B5600 · black and red"),
    ("GW-B5600-2", "GW-B5600-2 · blue"),
    ("GW-B5600BC-1B", "GW-B5600BC-1B · black composite"),
    ("GW-B5600HR-1", "GW-B5600HR-1 · black and red"),
    ("GW-B5600BL-1", "GW-B5600BL-1 · purple and green"),
    ("GW-B5600BP-1", "GW-B5600BP-1 · blue paisley"),
    ("GW-B5600MG-1", "GW-B5600MG-1 · midnight green"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPhase {
    Starting,
    BluetoothOff,
    Waiting,
    Connecting,
    Connected,
    Error,
}

impl ConnectionPhase {
    pub fn title(self) -> &'static str {
        match self {
            Self::Starting => "Starting Bluetooth",
            Self::BluetoothOff => "Bluetooth is off",
            Self::Waiting => "Waiting for the watch",
            Self::Connecting => "Connecting",
            Self::Connected => "Connected",
            Self::Error => "Bluetooth unavailable",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "snake_case")]
pub enum WatchButtonEvent {
    Connect,
    Time,
    Find,
    Automatic,
    Unknown,
}

impl WatchButtonEvent {
    pub const CONFIGURABLE: [Self; 4] = [Self::Find, Self::Time, Self::Connect, Self::Automatic];

    pub fn code(self) -> &'static str {
        match self {
            Self::Connect => "CNCT",
            Self::Time => "TIME",
            Self::Find => "FIND",
            Self::Automatic => "AUTO",
            Self::Unknown => "?",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Self::Connect => "Button C, hold for 3 seconds",
            Self::Time => "Button D, short press",
            Self::Find => "Button D, hold for 5 seconds",
            Self::Automatic => "Automatic connection",
            Self::Unknown => "Unknown gesture",
        }
    }

    pub fn instructions(self) -> &'static str {
        match self {
            Self::Connect => {
                "Hold the lower-left button for about 3 seconds until CNCT flashes. This is the full read-and-write connection."
            }
            Self::Time => {
                "Press the lower-right button once. TIME flashes while the computer sends the current time."
            }
            Self::Find => {
                "Hold the lower-right button for about 5 seconds until FIND flashes. Keep holding when RCVD appears."
            }
            Self::Automatic => {
                "Supported watches connect around 00:30, 06:30, 12:30, and 18:30 for time adjustment."
            }
            Self::Unknown => "The watch reported a gesture this version does not recognize.",
        }
    }

    pub fn button(self) -> Option<char> {
        match self {
            Self::Connect => Some('C'),
            Self::Time | Self::Find => Some('D'),
            Self::Automatic | Self::Unknown => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WatchSnapshot {
    pub battery_percent: Option<u8>,
    pub temperature_celsius: Option<i16>,
    pub home_city: Option<String>,
    pub timer_seconds: Option<u32>,
    pub last_time_sync: Option<DateTime<Utc>>,
    pub last_event: Option<WatchButtonEvent>,
    pub alarms: Vec<Alarm>,
    pub reminders: Vec<Reminder>,
    pub settings: Option<WatchSettings>,
    pub automatic_time_adjustment: Option<bool>,
}

impl Default for WatchSnapshot {
    fn default() -> Self {
        Self {
            battery_percent: None,
            temperature_celsius: None,
            home_city: None,
            timer_seconds: None,
            last_time_sync: None,
            last_event: None,
            alarms: Alarm::defaults(),
            reminders: Reminder::defaults(),
            settings: None,
            automatic_time_adjustment: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SavedWatch {
    pub id: String,
    pub detected_model: String,
    pub configured_model: Option<String>,
    pub nickname: String,
    pub manually_registered: bool,
    pub first_seen: DateTime<Utc>,
    pub last_seen: Option<DateTime<Utc>>,
    pub connection_count: u32,
    pub image_filename: Option<String>,
    pub allows_computer_actions: bool,
    pub snapshot: WatchSnapshot,
}

impl SavedWatch {
    pub fn manual(model: &str, nickname: &str) -> Self {
        let model = normalize_model(model);
        Self {
            id: format!("manual-{}", Uuid::new_v4()),
            detected_model: model.clone(),
            configured_model: Some(model),
            nickname: sanitize_single_line(nickname, 80),
            manually_registered: true,
            first_seen: Utc::now(),
            last_seen: None,
            connection_count: 0,
            image_filename: None,
            allows_computer_actions: false,
            snapshot: WatchSnapshot::default(),
        }
    }

    pub fn effective_model(&self) -> &str {
        self.configured_model
            .as_deref()
            .unwrap_or(&self.detected_model)
    }

    pub fn title(&self) -> String {
        if self.nickname.trim().is_empty() {
            compatible_watch_name(self.effective_model())
        } else {
            self.nickname.clone()
        }
    }

    pub fn is_linked(&self) -> bool {
        self.connection_count > 0
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RepeatMode {
    Once,
    Weekly,
    Monthly,
    Yearly,
}

impl RepeatMode {
    pub const ALL: [Self; 4] = [Self::Once, Self::Weekly, Self::Monthly, Self::Yearly];

    pub fn label(self) -> &'static str {
        match self {
            Self::Once => "Once or date range",
            Self::Weekly => "Every week",
            Self::Monthly => "Every month",
            Self::Yearly => "Every year",
        }
    }

    pub fn mask(self) -> u8 {
        match self {
            Self::Once => 0,
            Self::Weekly => 0x04,
            Self::Monthly => 0x10,
            Self::Yearly => 0x08,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "snake_case")]
pub enum Weekday {
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
}

impl Weekday {
    pub const ALL: [Self; 7] = [
        Self::Monday,
        Self::Tuesday,
        Self::Wednesday,
        Self::Thursday,
        Self::Friday,
        Self::Saturday,
        Self::Sunday,
    ];

    pub fn short(self) -> &'static str {
        match self {
            Self::Monday => "M",
            Self::Tuesday => "T",
            Self::Wednesday => "W",
            Self::Thursday => "T",
            Self::Friday => "F",
            Self::Saturday => "S",
            Self::Sunday => "S",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Monday => "Monday",
            Self::Tuesday => "Tuesday",
            Self::Wednesday => "Wednesday",
            Self::Thursday => "Thursday",
            Self::Friday => "Friday",
            Self::Saturday => "Saturday",
            Self::Sunday => "Sunday",
        }
    }

    pub fn mask(self) -> u8 {
        match self {
            Self::Sunday => 0x01,
            Self::Monday => 0x02,
            Self::Tuesday => 0x04,
            Self::Wednesday => 0x08,
            Self::Thursday => 0x10,
            Self::Friday => 0x20,
            Self::Saturday => 0x40,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Reminder {
    pub slot: u8,
    pub title: String,
    pub enabled: bool,
    pub repeat_mode: RepeatMode,
    pub start: NaiveDate,
    pub end: NaiveDate,
    pub days: BTreeSet<Weekday>,
}

impl Reminder {
    pub fn new(slot: u8) -> Self {
        let today = Utc::now().date_naive();
        Self {
            slot,
            title: String::new(),
            enabled: false,
            repeat_mode: RepeatMode::Once,
            start: today,
            end: today,
            days: BTreeSet::new(),
        }
    }

    pub fn defaults() -> Vec<Self> {
        (1..=5).map(Self::new).collect()
    }

    pub fn watch_title(&self) -> String {
        ascii_limited(&self.title, 18)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Alarm {
    pub number: u8,
    pub hour: u8,
    pub minute: u8,
    pub enabled: bool,
    pub hourly_chime: bool,
}

impl Alarm {
    pub fn new(number: u8) -> Self {
        Self {
            number,
            hour: 7,
            minute: 0,
            enabled: false,
            hourly_chime: false,
        }
    }

    pub fn defaults() -> Vec<Self> {
        (1..=5).map(Self::new).collect()
    }

    pub fn time_text(&self) -> String {
        format!("{:02}:{:02}", self.hour, self.minute)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WatchSettings {
    pub twenty_four_hour: bool,
    pub button_tone: bool,
    pub automatic_light: bool,
    pub power_saving: bool,
    pub long_light: bool,
    pub day_first_date: bool,
    pub language_index: u8,
}

impl Default for WatchSettings {
    fn default() -> Self {
        Self {
            twenty_four_hour: true,
            button_tone: true,
            automatic_light: false,
            power_saving: true,
            long_light: false,
            day_first_date: true,
            language_index: 0,
        }
    }
}

impl WatchSettings {
    pub const LANGUAGES: [&'static str; 6] = [
        "English", "Spanish", "French", "German", "Italian", "Russian",
    ];
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "snake_case")]
pub enum ActionKind {
    None,
    FindComputer,
    Speak,
    OpenUrl,
    OpenApplication,
    LockScreen,
    ToggleMute,
    PlayPause,
}

impl ActionKind {
    pub const ALL: [Self; 8] = [
        Self::None,
        Self::FindComputer,
        Self::Speak,
        Self::OpenUrl,
        Self::OpenApplication,
        Self::LockScreen,
        Self::ToggleMute,
        Self::PlayPause,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Self::None => "Do nothing",
            Self::FindComputer => "Find this computer",
            Self::Speak => "Speak a phrase",
            Self::OpenUrl => "Open a web link",
            Self::OpenApplication => "Open an application",
            Self::LockScreen => "Lock the screen",
            Self::ToggleMute => "Toggle mute",
            Self::PlayPause => "Play or pause media",
        }
    }

    pub fn needs_value(self) -> bool {
        matches!(self, Self::Speak | Self::OpenUrl | Self::OpenApplication)
    }

    pub fn value_label(self) -> &'static str {
        match self {
            Self::Speak => "Phrase spoken by the computer",
            Self::OpenUrl => "Web address (https://…)",
            Self::OpenApplication => "Application name or executable path",
            _ => "",
        }
    }

    pub fn help(self) -> &'static str {
        match self {
            Self::None => "No computer action runs for this gesture.",
            Self::FindComputer => {
                "Requests attention, plays an alert three times, and says “Here I am”."
            }
            Self::Speak => "Speaks the configured phrase using the operating system voice.",
            Self::OpenUrl => "Opens an HTTP or HTTPS address in the default browser.",
            Self::OpenApplication => {
                "Starts the selected application. Only trusted physical watches may run it."
            }
            Self::LockScreen => "Locks the current macOS or Windows session.",
            Self::ToggleMute => "Toggles the system output mute state when supported.",
            Self::PlayPause => "Sends the operating system media play/pause command.",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WatchAction {
    pub kind: ActionKind,
    pub value: String,
}

impl WatchAction {
    pub fn new(kind: ActionKind) -> Self {
        Self {
            kind,
            value: String::new(),
        }
    }

    pub fn summary(&self) -> String {
        match self.kind {
            ActionKind::Speak if !self.value.trim().is_empty() => {
                format!("Speak “{}”", sanitize_single_line(&self.value, 60))
            }
            ActionKind::OpenUrl | ActionKind::OpenApplication if !self.value.trim().is_empty() => {
                sanitize_single_line(&self.value, 60)
            }
            _ => self.kind.label().to_owned(),
        }
    }
}

impl Default for WatchAction {
    fn default() -> Self {
        Self::new(ActionKind::None)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActionsConfig {
    pub actions: BTreeMap<WatchButtonEvent, WatchAction>,
    pub sync_time_on: BTreeSet<WatchButtonEvent>,
    pub time_offset_seconds: i32,
}

impl Default for ActionsConfig {
    fn default() -> Self {
        let mut actions = BTreeMap::new();
        actions.insert(
            WatchButtonEvent::Find,
            WatchAction::new(ActionKind::FindComputer),
        );
        actions.insert(WatchButtonEvent::Time, WatchAction::default());
        actions.insert(WatchButtonEvent::Connect, WatchAction::default());
        actions.insert(WatchButtonEvent::Automatic, WatchAction::default());

        let sync_time_on = [WatchButtonEvent::Time, WatchButtonEvent::Automatic]
            .into_iter()
            .collect();

        Self {
            actions,
            sync_time_on,
            time_offset_seconds: 0,
        }
    }
}

impl ActionsConfig {
    pub fn action(&self, event: WatchButtonEvent) -> WatchAction {
        self.actions.get(&event).cloned().unwrap_or_default()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum PendingChange {
    Reminder(Reminder),
    Alarm(Alarm),
    Timer(u32),
    Settings(WatchSettings),
    AutomaticTimeAdjustment(bool),
    SyncTime,
}

impl PendingChange {
    pub fn id(&self) -> String {
        match self {
            Self::Reminder(reminder) => format!("reminder-{}", reminder.slot),
            Self::Alarm(alarm) => format!("alarm-{}", alarm.number),
            Self::Timer(_) => "timer".to_owned(),
            Self::Settings(_) => "settings".to_owned(),
            Self::AutomaticTimeAdjustment(_) => "automatic-time-adjustment".to_owned(),
            Self::SyncTime => "sync-time".to_owned(),
        }
    }

    pub fn summary(&self) -> String {
        match self {
            Self::Reminder(reminder) => format!(
                "Reminder {}: {}",
                reminder.slot,
                if reminder.watch_title().is_empty() {
                    "empty".to_owned()
                } else {
                    reminder.watch_title()
                }
            ),
            Self::Alarm(alarm) => format!(
                "Alarm {}: {}{}",
                alarm.number,
                alarm.time_text(),
                if alarm.enabled { "" } else { " (off)" }
            ),
            Self::Timer(seconds) => format!("Timer: {}", format_duration(*seconds)),
            Self::Settings(_) => "Watch settings".to_owned(),
            Self::AutomaticTimeAdjustment(enabled) => format!(
                "{} automatic time adjustment",
                if *enabled { "Enable" } else { "Disable" }
            ),
            Self::SyncTime => "Set the current time".to_owned(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ConnectionRecord {
    pub id: Uuid,
    pub date: DateTime<Utc>,
    pub watch_id: String,
    pub watch_model: String,
    pub event: WatchButtonEvent,
    pub battery_percent: Option<u8>,
    pub temperature_celsius: Option<i16>,
    pub time_synced: bool,
    pub applied_changes: Vec<String>,
    pub outcome: String,
}

impl ConnectionRecord {
    pub fn new(watch_id: String, watch_model: String, event: WatchButtonEvent) -> Self {
        Self {
            id: Uuid::new_v4(),
            date: Utc::now(),
            watch_id,
            watch_model,
            event,
            battery_percent: None,
            temperature_celsius: None,
            time_synced: false,
            applied_changes: Vec::new(),
            outcome: "Connected".to_owned(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AppData {
    pub schema_version: u32,
    pub watches: Vec<SavedWatch>,
    pub favorite_watch_id: Option<String>,
    pub preferred_model: String,
    pub actions: ActionsConfig,
    pub pending_changes: Vec<PendingChange>,
    pub history: Vec<ConnectionRecord>,
}

impl Default for AppData {
    fn default() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            watches: Vec::new(),
            favorite_watch_id: None,
            preferred_model: "GW-B5600".to_owned(),
            actions: ActionsConfig::default(),
            pending_changes: Vec::new(),
            history: Vec::new(),
        }
    }
}

impl AppData {
    pub fn panel_watch(&self) -> Option<&SavedWatch> {
        self.favorite_watch_id
            .as_deref()
            .and_then(|favorite| self.watches.iter().find(|watch| watch.id == favorite))
            .or_else(|| {
                self.watches
                    .iter()
                    .max_by_key(|watch| watch.last_seen.unwrap_or(watch.first_seen))
            })
    }

    pub fn panel_watch_mut(&mut self) -> Option<&mut SavedWatch> {
        let id = self.panel_watch().map(|watch| watch.id.clone())?;
        self.watches.iter_mut().find(|watch| watch.id == id)
    }

    pub fn queue_change(&mut self, change: PendingChange) {
        let id = change.id();
        self.pending_changes.retain(|existing| existing.id() != id);
        self.pending_changes.push(change);
    }

    pub fn trim_for_storage(&mut self) {
        self.schema_version = SCHEMA_VERSION;
        self.preferred_model = normalize_model(&self.preferred_model);

        let mut identifiers = BTreeSet::new();
        self.watches.truncate(MAXIMUM_WATCHES);
        self.watches.retain_mut(|watch| {
            watch.id = sanitize_single_line(&watch.id, 256);
            if watch.id.is_empty() || !identifiers.insert(watch.id.clone()) {
                return false;
            }
            watch.nickname = sanitize_single_line(&watch.nickname, 80);
            watch.detected_model = normalize_model(&watch.detected_model);
            if let Some(configured) = &watch.configured_model {
                watch.configured_model = Some(normalize_model(configured));
            }
            watch.allows_computer_actions &= watch.is_linked() && !watch.manually_registered;
            normalize_snapshot(&mut watch.snapshot);
            true
        });

        if !self
            .favorite_watch_id
            .as_ref()
            .is_some_and(|favorite| identifiers.contains(favorite))
        {
            self.favorite_watch_id = None;
        }

        self.actions
            .actions
            .retain(|event, _| WatchButtonEvent::CONFIGURABLE.contains(event));
        for event in WatchButtonEvent::CONFIGURABLE {
            let action = self.actions.actions.entry(event).or_default();
            action.value = sanitize_single_line(&action.value, 240);
            if !action.kind.needs_value() {
                action.value.clear();
            }
        }
        self.actions
            .sync_time_on
            .retain(|event| WatchButtonEvent::CONFIGURABLE.contains(event));
        self.actions.time_offset_seconds = self.actions.time_offset_seconds.clamp(-300, 300);

        let mut normalized_pending = Vec::new();
        for mut change in std::mem::take(&mut self.pending_changes)
            .into_iter()
            .take(MAXIMUM_PENDING_CHANGES)
        {
            normalize_pending_change(&mut change);
            let id = change.id();
            normalized_pending.retain(|existing: &PendingChange| existing.id() != id);
            normalized_pending.push(change);
        }
        self.pending_changes = normalized_pending;

        self.history.truncate(MAXIMUM_HISTORY_RECORDS);
        self.history.retain_mut(|record| {
            record.watch_id = sanitize_single_line(&record.watch_id, 256);
            record.watch_model = normalize_model(&record.watch_model);
            record.battery_percent = record.battery_percent.filter(|value| *value <= 100);
            record.temperature_celsius = record
                .temperature_celsius
                .map(|value| value.clamp(-100, 150));
            record.applied_changes.truncate(32);
            for summary in &mut record.applied_changes {
                *summary = sanitize_single_line(summary, 120);
            }
            record.outcome = sanitize_single_line(&record.outcome, 120);
            !record.watch_id.is_empty() && identifiers.contains(&record.watch_id)
        });
    }

    pub fn demo() -> Self {
        let now = Utc::now();
        let id = "demo-compatible-watch".to_owned();
        let mut snapshot = WatchSnapshot {
            battery_percent: Some(100),
            temperature_celsius: Some(31),
            home_city: Some("MADRID".to_owned()),
            timer_seconds: Some(601),
            last_time_sync: Some(now - chrono::Duration::hours(5)),
            last_event: Some(WatchButtonEvent::Connect),
            automatic_time_adjustment: Some(true),
            settings: Some(WatchSettings::default()),
            ..WatchSnapshot::default()
        };
        snapshot.alarms[0] = Alarm {
            number: 1,
            hour: 6,
            minute: 20,
            enabled: true,
            hourly_chime: false,
        };
        snapshot.reminders[0].title = "Game festival".to_owned();
        snapshot.reminders[0].enabled = true;

        let watch = SavedWatch {
            id: id.clone(),
            detected_model: "GW-B5600".to_owned(),
            configured_model: Some("GW-B5600BP-1".to_owned()),
            nickname: "Daily watch".to_owned(),
            manually_registered: false,
            first_seen: now - chrono::Duration::days(180),
            last_seen: Some(now - chrono::Duration::minutes(2)),
            connection_count: 84,
            image_filename: None,
            allows_computer_actions: true,
            snapshot,
        };

        let mut actions = ActionsConfig::default();
        actions.actions.insert(
            WatchButtonEvent::Connect,
            WatchAction {
                kind: ActionKind::Speak,
                value: "Time for a break".to_owned(),
            },
        );
        actions.actions.insert(
            WatchButtonEvent::Time,
            WatchAction::new(ActionKind::LockScreen),
        );

        let history = [
            (WatchButtonEvent::Connect, 2),
            (WatchButtonEvent::Time, 5 * 60),
            (WatchButtonEvent::Automatic, 11 * 60),
            (WatchButtonEvent::Find, 26 * 60),
        ]
        .into_iter()
        .map(|(event, minutes)| {
            let mut record = ConnectionRecord::new(id.clone(), "GW-B5600BP-1".to_owned(), event);
            record.date = now - chrono::Duration::minutes(minutes);
            record.battery_percent = Some(100);
            record.temperature_celsius = Some(31);
            record.time_synced = matches!(
                event,
                WatchButtonEvent::Connect | WatchButtonEvent::Time | WatchButtonEvent::Automatic
            );
            record.outcome = "Completed".to_owned();
            record
        })
        .collect();

        Self {
            watches: vec![watch],
            favorite_watch_id: Some(id),
            preferred_model: "GW-B5600BP-1".to_owned(),
            actions,
            history,
            ..Self::default()
        }
    }
}

fn normalize_snapshot(snapshot: &mut WatchSnapshot) {
    snapshot.battery_percent = snapshot.battery_percent.filter(|value| *value <= 100);
    snapshot.temperature_celsius = snapshot
        .temperature_celsius
        .map(|value| value.clamp(-100, 150));
    snapshot.home_city = snapshot
        .home_city
        .as_deref()
        .map(|city| sanitize_single_line(city, 48))
        .filter(|city| !city.is_empty());
    snapshot.timer_seconds = snapshot.timer_seconds.map(|seconds| seconds.min(86_399));

    let mut alarms = Alarm::defaults();
    for mut alarm in std::mem::take(&mut snapshot.alarms) {
        if (1..=5).contains(&alarm.number) {
            alarm.hour = alarm.hour.min(23);
            alarm.minute = alarm.minute.min(59);
            let index = usize::from(alarm.number - 1);
            alarms[index] = alarm;
        }
    }
    snapshot.alarms = alarms;

    let mut reminders = Reminder::defaults();
    for mut reminder in std::mem::take(&mut snapshot.reminders) {
        if (1..=5).contains(&reminder.slot) {
            reminder.title = sanitize_single_line(&reminder.title, 80);
            if reminder.end < reminder.start {
                reminder.end = reminder.start;
            }
            let index = usize::from(reminder.slot - 1);
            reminders[index] = reminder;
        }
    }
    snapshot.reminders = reminders;

    if let Some(settings) = &mut snapshot.settings {
        settings.language_index = settings
            .language_index
            .min((WatchSettings::LANGUAGES.len() - 1) as u8);
    }
}

fn normalize_pending_change(change: &mut PendingChange) {
    match change {
        PendingChange::Reminder(reminder) => {
            reminder.slot = reminder.slot.clamp(1, 5);
            reminder.title = sanitize_single_line(&reminder.title, 80);
            if reminder.end < reminder.start {
                reminder.end = reminder.start;
            }
        }
        PendingChange::Alarm(alarm) => {
            alarm.number = alarm.number.clamp(1, 5);
            alarm.hour = alarm.hour.min(23);
            alarm.minute = alarm.minute.min(59);
        }
        PendingChange::Timer(seconds) => *seconds = (*seconds).min(86_399),
        PendingChange::Settings(settings) => {
            settings.language_index = settings
                .language_index
                .min((WatchSettings::LANGUAGES.len() - 1) as u8);
        }
        PendingChange::AutomaticTimeAdjustment(_) | PendingChange::SyncTime => {}
    }
}

pub fn normalize_model(value: &str) -> String {
    let mut model = sanitize_single_line(value, 48)
        .replace('_', "-")
        .to_ascii_uppercase();
    for prefix in ["CASIO ", "CASIO-"] {
        if let Some(without_brand) = model.strip_prefix(prefix) {
            model = without_brand.to_owned();
            break;
        }
    }
    if model.is_empty() {
        "UNKNOWN".to_owned()
    } else {
        model
    }
}

pub fn model_from_bluetooth_name(name: &str) -> String {
    let normalized = name.trim().replace('_', "-").to_ascii_uppercase();
    normalized
        .split_whitespace()
        .find(|part| part.contains('-') && part.chars().any(|character| character.is_ascii_digit()))
        .map(normalize_model)
        .unwrap_or_else(|| {
            let without_brand = normalized
                .split_whitespace()
                .filter(|part| *part != "CASIO")
                .collect::<Vec<_>>()
                .join(" ");
            if without_brand.is_empty() {
                "GW-B5600".to_owned()
            } else {
                normalize_model(&without_brand)
            }
        })
}

pub fn compatible_watch_name(model: &str) -> String {
    format!("CASIO-compatible {}", normalize_model(model))
}

pub fn same_watch_family(left: &str, right: &str) -> bool {
    let left = normalize_model(left);
    let right = normalize_model(right);
    (left.starts_with("GW-B5600") && right.starts_with("GW-B5600")) || left == right
}

pub fn sanitize_single_line(value: &str, limit: usize) -> String {
    value
        .chars()
        .map(|character| {
            if character == '\n' || character == '\r' {
                ' '
            } else {
                character
            }
        })
        .filter(|character| !character.is_control())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(limit)
        .collect()
}

pub fn ascii_limited(value: &str, limit: usize) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii() && !character.is_ascii_control())
        .take(limit)
        .collect()
}

pub fn format_duration(seconds: u32) -> String {
    let hours = seconds / 3_600;
    let minutes = (seconds % 3_600) / 60;
    let seconds = seconds % 60;
    if hours > 0 {
        format!("{hours}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes}:{seconds:02}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_a_model_without_treating_the_brand_as_part_of_it() {
        assert_eq!(model_from_bluetooth_name("CASIO GW-B5600"), "GW-B5600");
        assert_eq!(
            model_from_bluetooth_name("CASIO_GW-B5600BP-1"),
            "GW-B5600BP-1"
        );
    }

    #[test]
    fn action_trust_is_off_for_manually_registered_watches() {
        let watch = SavedWatch::manual("GW-B5600", "Desk watch");
        assert!(!watch.allows_computer_actions);
        assert!(!watch.is_linked());
    }

    #[test]
    fn reminder_titles_are_ascii_and_limited_for_the_watch() {
        let mut reminder = Reminder::new(1);
        reminder.title = "Coffee break — tomorrow at seventeen".to_owned();
        assert_eq!(reminder.watch_title(), "Coffee break  tomo");
        assert!(reminder.watch_title().len() <= 18);
    }

    #[test]
    fn queued_changes_replace_older_values_for_the_same_slot() {
        let mut data = AppData::default();
        data.queue_change(PendingChange::Timer(60));
        data.queue_change(PendingChange::Timer(120));
        assert_eq!(data.pending_changes, vec![PendingChange::Timer(120)]);
    }

    #[test]
    fn loaded_state_is_bounded_and_manual_records_cannot_be_trusted() {
        let mut data = AppData::default();
        let mut watch = SavedWatch::manual("casio_gw-b5600", "Desk\nwatch");
        watch.connection_count = 99;
        watch.allows_computer_actions = true;
        watch.snapshot.battery_percent = Some(255);
        watch.snapshot.timer_seconds = Some(u32::MAX);
        data.watches.push(watch);
        data.actions.time_offset_seconds = i32::MAX;

        data.trim_for_storage();

        assert_eq!(data.watches[0].effective_model(), "GW-B5600");
        assert_eq!(data.watches[0].nickname, "Desk watch");
        assert!(!data.watches[0].allows_computer_actions);
        assert_eq!(data.watches[0].snapshot.battery_percent, None);
        assert_eq!(data.watches[0].snapshot.timer_seconds, Some(86_399));
        assert_eq!(data.actions.time_offset_seconds, 300);
    }
}
