use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use btleplug::api::{
    Central, CentralEvent, CharPropFlags, Characteristic, Manager as _, Peripheral as _,
    ScanFilter, ValueNotification, WriteType,
};
use btleplug::platform::{Adapter, Manager, Peripheral};
use chrono::{Local, Utc};
use futures_util::{Stream, StreamExt};
use tokio::sync::mpsc;
use tokio::time::timeout;
use uuid::Uuid;

use crate::actions;
use crate::state::SharedState;
use watchbridge_core::model::{
    ConnectionPhase, ConnectionRecord, PendingChange, SavedWatch, WatchButtonEvent, WatchSnapshot,
    model_from_bluetooth_name, same_watch_family,
};
use watchbridge_core::protocol::{self, code};

const SERVICE_UUID: Uuid = Uuid::from_u128(0x26EB000D_B012_49A8_B1F8_394FB2032B0F);
const REQUEST_UUID: Uuid = Uuid::from_u128(0x26EB002C_B012_49A8_B1F8_394FB2032B0F);
const FEATURES_UUID: Uuid = Uuid::from_u128(0x26EB002D_B012_49A8_B1F8_394FB2032B0F);
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(18);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(12);

#[derive(Debug, Clone, Copy)]
pub enum BluetoothCommand {
    ScanNow,
    Disconnect,
    Shutdown,
}

#[derive(Clone)]
pub struct BluetoothController {
    sender: mpsc::UnboundedSender<BluetoothCommand>,
}

impl BluetoothController {
    pub fn start(shared: Arc<SharedState>) -> Self {
        let (sender, receiver) = mpsc::unbounded_channel();
        std::thread::Builder::new()
            .name("watchbridge-bluetooth".to_owned())
            .spawn(move || {
                let runtime = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build();
                match runtime {
                    Ok(runtime) => {
                        if let Err(error) =
                            runtime.block_on(bluetooth_loop(shared.clone(), receiver))
                        {
                            let mut status = shared.runtime.write();
                            status.set(ConnectionPhase::Error, "Bluetooth could not be started");
                            status.push_trace(error.to_string());
                        }
                    }
                    Err(error) => {
                        let mut status = shared.runtime.write();
                        status.set(
                            ConnectionPhase::Error,
                            "The Bluetooth worker could not be created",
                        );
                        status.push_trace(error.to_string());
                    }
                }
            })
            .expect("failed to start the Bluetooth worker");
        Self { sender }
    }

    pub fn send(&self, command: BluetoothCommand) {
        let _ = self.sender.send(command);
    }
}

async fn bluetooth_loop(
    shared: Arc<SharedState>,
    mut commands: mpsc::UnboundedReceiver<BluetoothCommand>,
) -> Result<()> {
    let manager = Manager::new()
        .await
        .context("could not access the Bluetooth manager")?;
    let adapters = manager
        .adapters()
        .await
        .context("could not list Bluetooth adapters")?;
    let adapter = adapters
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("no Bluetooth Low Energy adapter was found"))?;
    let state = adapter
        .adapter_state()
        .await
        .context("could not read the Bluetooth state")?;
    if state != btleplug::api::CentralState::PoweredOn {
        let mut runtime = shared.runtime.write();
        runtime.set(
            ConnectionPhase::BluetoothOff,
            "Turn on Bluetooth to wait for the watch",
        );
    }

    let mut events = adapter
        .events()
        .await
        .context("could not subscribe to Bluetooth events")?;
    start_scan(&adapter, &shared).await?;

    loop {
        tokio::select! {
            command = commands.recv() => {
                match command {
                    Some(BluetoothCommand::ScanNow) => {
                        start_scan(&adapter, &shared).await?;
                    }
                    Some(BluetoothCommand::Disconnect) => {
                        disconnect_all(&adapter).await;
                        start_scan(&adapter, &shared).await?;
                    }
                    Some(BluetoothCommand::Shutdown) | None => {
                        let _ = adapter.stop_scan().await;
                        disconnect_all(&adapter).await;
                        return Ok(());
                    }
                }
            }
            event = events.next() => {
                let Some(event) = event else {
                    bail!("the Bluetooth event stream closed unexpectedly");
                };
                match event {
                    CentralEvent::StateUpdate(state) => {
                        match state {
                            btleplug::api::CentralState::PoweredOn => {
                                start_scan(&adapter, &shared).await?;
                            }
                            btleplug::api::CentralState::PoweredOff => {
                                let mut runtime = shared.runtime.write();
                                runtime.is_scanning = false;
                                runtime.set(ConnectionPhase::BluetoothOff, "Turn on Bluetooth to wait for the watch");
                            }
                            _ => {}
                        }
                    }
                    CentralEvent::DeviceDiscovered(id) | CentralEvent::DeviceUpdated(id) => {
                        let peripheral = adapter.peripheral(&id).await?;
                        if let Some(name) = compatible_name(&peripheral).await? {
                            let _ = adapter.stop_scan().await;
                            shared.runtime.write().is_scanning = false;
                            if let Err(error) = run_session(peripheral, name, shared.clone()).await {
                                shared.trace(format!("Connection ended: {error}"));
                            }
                            if shared.runtime.read().phase != ConnectionPhase::BluetoothOff {
                                start_scan(&adapter, &shared).await?;
                            }
                        }
                    }
                    CentralEvent::DeviceDisconnected(id) => {
                        let identifier = id.to_string();
                        let mut runtime = shared.runtime.write();
                        if runtime.connected_watch_id.as_deref() == Some(&identifier) {
                            runtime.connected_watch_id = None;
                            runtime.set(ConnectionPhase::Waiting, "Waiting for the watch");
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

async fn start_scan(adapter: &Adapter, shared: &SharedState) -> Result<()> {
    adapter
        .start_scan(ScanFilter::default())
        .await
        .context("could not start the Bluetooth scan")?;
    let mut runtime = shared.runtime.write();
    runtime.is_scanning = true;
    runtime.set(ConnectionPhase::Waiting, "Waiting for the watch");
    runtime.push_trace("Bluetooth scan started");
    Ok(())
}

async fn disconnect_all(adapter: &Adapter) {
    if let Ok(peripherals) = adapter.peripherals().await {
        for peripheral in peripherals {
            if peripheral.is_connected().await.unwrap_or(false) {
                let _ = peripheral.disconnect().await;
            }
        }
    }
}

async fn compatible_name(peripheral: &Peripheral) -> Result<Option<String>> {
    let properties = peripheral.properties().await?;
    let Some(properties) = properties else {
        return Ok(None);
    };
    let advertised_service = properties.services.contains(&SERVICE_UUID);
    let name = properties.local_name.unwrap_or_default();
    let compatible_name = name.to_ascii_uppercase().starts_with("CASIO");
    if advertised_service || compatible_name {
        Ok(Some(if name.is_empty() {
            "Compatible Bluetooth watch".to_owned()
        } else {
            name
        }))
    } else {
        Ok(None)
    }
}

struct WatchConnection {
    peripheral: Peripheral,
    request_characteristic: Characteristic,
    features_characteristic: Characteristic,
    notifications: Pin<Box<dyn Stream<Item = ValueNotification> + Send>>,
    shared: Arc<SharedState>,
}

impl WatchConnection {
    async fn open(peripheral: Peripheral, shared: Arc<SharedState>) -> Result<Self> {
        timeout(CONNECTION_TIMEOUT, peripheral.connect())
            .await
            .context("the watch did not connect in time")??;
        timeout(CONNECTION_TIMEOUT, peripheral.discover_services())
            .await
            .context("service discovery timed out")??;

        let characteristics = peripheral.characteristics();
        let request_characteristic = characteristics
            .iter()
            .find(|characteristic| characteristic.uuid == REQUEST_UUID)
            .cloned()
            .ok_or_else(|| anyhow!("the request characteristic is missing"))?;
        let features_characteristic = characteristics
            .iter()
            .find(|characteristic| characteristic.uuid == FEATURES_UUID)
            .cloned()
            .ok_or_else(|| anyhow!("the feature characteristic is missing"))?;

        let notifications = peripheral.notifications().await?;
        for characteristic in characteristics.iter().filter(|characteristic| {
            characteristic
                .properties
                .intersects(CharPropFlags::NOTIFY | CharPropFlags::INDICATE)
        }) {
            peripheral.subscribe(characteristic).await?;
        }

        Ok(Self {
            peripheral,
            request_characteristic,
            features_characteristic,
            notifications,
            shared,
        })
    }

    async fn request(&mut self, bytes: &[u8], expected: u8, deadline: Duration) -> Result<Vec<u8>> {
        self.shared.trace(format!(
            "Request {:02X}",
            bytes.first().copied().unwrap_or_default()
        ));
        self.peripheral
            .write(
                &self.request_characteristic,
                bytes,
                WriteType::WithoutResponse,
            )
            .await?;
        timeout(deadline, self.wait_for(expected))
            .await
            .with_context(|| format!("command {expected:02X} timed out"))?
    }

    async fn wait_for(&mut self, expected: u8) -> Result<Vec<u8>> {
        while let Some(notification) = self.notifications.next().await {
            let data = notification.value;
            if data.is_empty() {
                continue;
            }
            self.shared.trace(format!("Response {:02X}", data[0]));
            if protocol::is_app_info_challenge(&data) {
                self.peripheral
                    .write(
                        &self.features_characteristic,
                        &protocol::APP_INFO_RESPONSE,
                        WriteType::WithResponse,
                    )
                    .await?;
            }
            if data[0] == expected {
                return Ok(data);
            }
        }
        bail!("the watch stopped sending notifications")
    }

    async fn write(&self, bytes: &[u8], deadline: Duration) -> Result<()> {
        self.shared.trace(format!(
            "Write {:02X}",
            bytes.first().copied().unwrap_or_default()
        ));
        timeout(
            deadline,
            self.peripheral.write(
                &self.features_characteristic,
                bytes,
                WriteType::WithResponse,
            ),
        )
        .await
        .context("the watch write timed out")??;
        Ok(())
    }

    async fn echo(&mut self, request: &[u8]) -> Option<Vec<u8>> {
        let expected = *request.first()?;
        let response = self
            .request(request, expected, Duration::from_secs(4))
            .await
            .ok()?;
        self.write(&response, Duration::from_secs(4)).await.ok()?;
        Some(response)
    }
}

async fn run_session(
    peripheral: Peripheral,
    bluetooth_name: String,
    shared: Arc<SharedState>,
) -> Result<()> {
    let identifier = peripheral.id().to_string();
    {
        let mut runtime = shared.runtime.write();
        runtime.set(
            ConnectionPhase::Connecting,
            format!("Connecting to {bluetooth_name}"),
        );
        runtime.push_trace(format!("Compatible watch found: {bluetooth_name}"));
    }

    let mut connection = match WatchConnection::open(peripheral.clone(), shared.clone()).await {
        Ok(connection) => connection,
        Err(error) => {
            let _ = peripheral.disconnect().await;
            return Err(error);
        }
    };

    let features = connection
        .request(&[code::BLE_FEATURES], code::BLE_FEATURES, REQUEST_TIMEOUT)
        .await?;
    let event = protocol::decode_button(&features);
    let watch_id = remember_watch(&shared, &identifier, &bluetooth_name);
    let (watch_model, trusted, action, should_sync) = {
        let data = shared.data.read();
        let watch = data
            .watches
            .iter()
            .find(|watch| watch.id == watch_id)
            .ok_or_else(|| anyhow!("the connected watch was removed before setup completed"))?;
        (
            watch.effective_model().to_owned(),
            watch.allows_computer_actions,
            data.actions.action(event),
            data.actions.sync_time_on.contains(&event),
        )
    };

    {
        let mut runtime = shared.runtime.write();
        runtime.connected_watch_id = Some(watch_id.clone());
        runtime.set(
            ConnectionPhase::Connected,
            format!("Connected · {}", event.title()),
        );
    }

    let _ = connection
        .request(&[code::APP_INFO], code::APP_INFO, Duration::from_secs(5))
        .await;

    if trusted && action.kind != watchbridge_core::model::ActionKind::None {
        let action_shared = shared.clone();
        tokio::spawn(async move {
            let outcome = actions::run(action).await;
            action_shared.runtime.write().last_action_result = Some(outcome.summary);
        });
    } else if !trusted && action.kind != watchbridge_core::model::ActionKind::None {
        shared.trace("Computer action blocked until this physical watch is trusted");
    }

    let mut record = ConnectionRecord::new(watch_id.clone(), watch_model, event);
    if let Ok(condition) = connection
        .request(&[code::CONDITION], code::CONDITION, REQUEST_TIMEOUT)
        .await
        && let Some((battery, temperature)) = protocol::decode_condition(&condition)
    {
        record.battery_percent = Some(battery);
        record.temperature_celsius = Some(temperature);
        update_snapshot(&shared, &watch_id, |snapshot| {
            snapshot.battery_percent = Some(battery);
            snapshot.temperature_celsius = Some(temperature);
            snapshot.last_event = Some(event);
        });
    }

    if event == WatchButtonEvent::Connect
        && let Err(error) = refresh_all(&mut connection, &shared, &watch_id).await
    {
        shared.trace(format!("Full refresh was incomplete: {error}"));
    }

    let pending = shared.data.read().pending_changes.clone();
    for change in pending
        .iter()
        .filter(|change| !matches!(change, PendingChange::SyncTime))
    {
        match apply_change(&mut connection, &shared, &watch_id, change).await {
            Ok(()) => {
                record.applied_changes.push(change.summary());
                shared
                    .data
                    .write()
                    .pending_changes
                    .retain(|pending| pending.id() != change.id());
                shared.save();
            }
            Err(error) => {
                shared.trace(format!("Pending {} was kept: {error}", change.id()));
                break;
            }
        }
    }

    let explicit_sync = pending
        .iter()
        .any(|change| matches!(change, PendingChange::SyncTime));
    if should_sync || explicit_sync {
        match write_time(&mut connection, &shared, &watch_id).await {
            Ok(()) => {
                record.time_synced = true;
                shared
                    .data
                    .write()
                    .pending_changes
                    .retain(|change| !matches!(change, PendingChange::SyncTime));
            }
            Err(error) if !connection.peripheral.is_connected().await.unwrap_or(false) => {
                record.time_synced = true;
                shared.trace(format!("Time packet sent before disconnect: {error}"));
            }
            Err(error) => shared.trace(format!("Time sync failed: {error}")),
        }
    }

    record.outcome = "Completed".to_owned();
    {
        let mut data = shared.data.write();
        if let Some(watch) = data.watches.iter_mut().find(|watch| watch.id == watch_id) {
            watch.last_seen = Some(Utc::now());
            watch.snapshot.last_event = Some(event);
        }
        data.history.insert(0, record);
        data.history.truncate(300);
    }
    shared.save();

    let _ = peripheral.disconnect().await;
    {
        let mut runtime = shared.runtime.write();
        runtime.connected_watch_id = None;
        runtime.set(ConnectionPhase::Waiting, "Saved the latest watch state");
    }
    Ok(())
}

fn remember_watch(shared: &SharedState, identifier: &str, bluetooth_name: &str) -> String {
    let detected_model = model_from_bluetooth_name(bluetooth_name);
    let now = Utc::now();
    let mut data = shared.data.write();

    let index = if let Some(index) = data.watches.iter().position(|watch| watch.id == identifier) {
        index
    } else {
        let manual_matches: Vec<usize> = data
            .watches
            .iter()
            .enumerate()
            .filter(|(_, watch)| {
                watch.manually_registered
                    && !watch.is_linked()
                    && same_watch_family(watch.effective_model(), &detected_model)
            })
            .map(|(index, _)| index)
            .collect();
        if manual_matches.len() == 1 {
            let index = manual_matches[0];
            let previous_id = data.watches[index].id.clone();
            data.watches[index].id = identifier.to_owned();
            if data.favorite_watch_id.as_deref() == Some(&previous_id) {
                data.favorite_watch_id = Some(identifier.to_owned());
            }
            index
        } else {
            let configured_model = data.preferred_model.clone();
            data.watches.push(SavedWatch {
                id: identifier.to_owned(),
                detected_model: detected_model.clone(),
                configured_model: Some(configured_model),
                nickname: String::new(),
                manually_registered: false,
                first_seen: now,
                last_seen: Some(now),
                connection_count: 0,
                image_filename: None,
                allows_computer_actions: false,
                snapshot: WatchSnapshot::default(),
            });
            data.watches.len() - 1
        }
    };

    let watch_id = {
        let watch = &mut data.watches[index];
        watch.detected_model = detected_model;
        watch.manually_registered = false;
        watch.last_seen = Some(now);
        watch.connection_count = watch.connection_count.saturating_add(1);
        watch.id.clone()
    };
    if data.favorite_watch_id.is_none() {
        data.favorite_watch_id = Some(watch_id.clone());
    }
    drop(data);
    shared.save();
    watch_id
}

fn update_snapshot(shared: &SharedState, watch_id: &str, update: impl FnOnce(&mut WatchSnapshot)) {
    let mut data = shared.data.write();
    if let Some(watch) = data.watches.iter_mut().find(|watch| watch.id == watch_id) {
        update(&mut watch.snapshot);
    }
}

async fn refresh_all(
    connection: &mut WatchConnection,
    shared: &SharedState,
    watch_id: &str,
) -> Result<()> {
    if let Ok(raw) = connection
        .request(
            &[code::WATCH_NAME],
            code::WATCH_NAME,
            Duration::from_secs(6),
        )
        .await
    {
        let name = protocol::decode_name(&raw);
        if !name.is_empty() {
            let model = model_from_bluetooth_name(&name);
            if let Some(watch) = shared
                .data
                .write()
                .watches
                .iter_mut()
                .find(|watch| watch.id == watch_id)
            {
                watch.detected_model = model;
            }
        }
    }

    let city = connection
        .request(
            &[code::WORLD_CITIES, 0],
            code::WORLD_CITIES,
            REQUEST_TIMEOUT,
        )
        .await
        .map(|packet| protocol::decode_city(&packet))?;
    let timer = connection
        .request(&[code::TIMER], code::TIMER, REQUEST_TIMEOUT)
        .await
        .ok()
        .and_then(|packet| protocol::decode_timer(&packet));
    let alarms = read_alarms(connection).await?;
    let settings = connection
        .request(
            &[code::BASIC_SETTINGS],
            code::BASIC_SETTINGS,
            REQUEST_TIMEOUT,
        )
        .await
        .ok()
        .and_then(|packet| protocol::decode_settings(&packet));
    let automatic_time_adjustment = connection
        .request(
            &[code::TIME_ADJUSTMENT],
            code::TIME_ADJUSTMENT,
            REQUEST_TIMEOUT,
        )
        .await
        .ok()
        .and_then(|packet| protocol::decode_automatic_time_adjustment(&packet));

    let mut reminders = Vec::new();
    for slot in 1..=5 {
        let title = connection
            .request(
                &[code::REMINDER_TITLE, slot],
                code::REMINDER_TITLE,
                REQUEST_TIMEOUT,
            )
            .await?;
        let time = connection
            .request(
                &[code::REMINDER_TIME, slot],
                code::REMINDER_TIME,
                REQUEST_TIMEOUT,
            )
            .await?;
        let mut reminder = watchbridge_core::model::Reminder::new(slot);
        reminder.title = protocol::decode_reminder_title(&title).unwrap_or_default();
        let _ = protocol::decode_reminder_time(&time, &mut reminder);
        reminders.push(reminder);
    }

    update_snapshot(shared, watch_id, |snapshot| {
        snapshot.home_city = (!city.is_empty()).then_some(city);
        snapshot.timer_seconds = timer;
        snapshot.alarms = alarms;
        snapshot.settings = settings;
        snapshot.automatic_time_adjustment = automatic_time_adjustment;
        snapshot.reminders = reminders;
    });
    shared.save();
    Ok(())
}

async fn read_alarms(
    connection: &mut WatchConnection,
) -> Result<Vec<watchbridge_core::model::Alarm>> {
    let first = connection
        .request(&[code::ALARM_1], code::ALARM_1, REQUEST_TIMEOUT)
        .await?;
    let rest = connection
        .request(&[code::ALARMS_2_TO_5], code::ALARMS_2_TO_5, REQUEST_TIMEOUT)
        .await?;
    protocol::decode_alarms(&first, &rest).ok_or_else(|| anyhow!("the alarm response was invalid"))
}

async fn apply_change(
    connection: &mut WatchConnection,
    shared: &SharedState,
    watch_id: &str,
    change: &PendingChange,
) -> Result<()> {
    match change {
        PendingChange::Reminder(reminder) => {
            connection
                .write(&protocol::encode_reminder_title(reminder), REQUEST_TIMEOUT)
                .await?;
            connection
                .write(&protocol::encode_reminder_time(reminder), REQUEST_TIMEOUT)
                .await?;
            update_snapshot(shared, watch_id, |snapshot| {
                if let Some(slot) = snapshot
                    .reminders
                    .get_mut(usize::from(reminder.slot.saturating_sub(1)))
                {
                    *slot = reminder.clone();
                }
            });
        }
        PendingChange::Alarm(alarm) => {
            let mut alarms = read_alarms(connection).await?;
            let index = usize::from(alarm.number.saturating_sub(1));
            let target = alarms
                .get_mut(index)
                .ok_or_else(|| anyhow!("invalid alarm slot"))?;
            *target = alarm.clone();
            let (first, rest) = protocol::encode_alarms(&alarms)
                .ok_or_else(|| anyhow!("exactly five alarm slots are required"))?;
            connection.write(&first, REQUEST_TIMEOUT).await?;
            connection.write(&rest, REQUEST_TIMEOUT).await?;
            update_snapshot(shared, watch_id, |snapshot| snapshot.alarms = alarms);
        }
        PendingChange::Timer(seconds) => {
            connection
                .write(&protocol::encode_timer(*seconds), REQUEST_TIMEOUT)
                .await?;
            update_snapshot(shared, watch_id, |snapshot| {
                snapshot.timer_seconds = Some(*seconds)
            });
        }
        PendingChange::Settings(settings) => {
            connection
                .write(&protocol::encode_settings(settings), REQUEST_TIMEOUT)
                .await?;
            update_snapshot(shared, watch_id, |snapshot| {
                snapshot.settings = Some(settings.clone())
            });
        }
        PendingChange::AutomaticTimeAdjustment(enabled) => {
            let current = connection
                .request(
                    &[code::TIME_ADJUSTMENT],
                    code::TIME_ADJUSTMENT,
                    REQUEST_TIMEOUT,
                )
                .await?;
            let packet = protocol::encode_automatic_time_adjustment(&current, *enabled, 30);
            connection.write(&packet, REQUEST_TIMEOUT).await?;
            update_snapshot(shared, watch_id, |snapshot| {
                snapshot.automatic_time_adjustment = Some(*enabled)
            });
        }
        PendingChange::SyncTime => write_time(connection, shared, watch_id).await?,
    }
    Ok(())
}

async fn write_time(
    connection: &mut WatchConnection,
    shared: &SharedState,
    watch_id: &str,
) -> Result<()> {
    for state in [0, 2, 4] {
        let _ = connection.echo(&[code::DST_WATCH_STATE, state]).await;
    }
    for city in 0..6 {
        let _ = connection.echo(&[code::DST_SETTING, city]).await;
    }
    let mut home_city = None;
    for city in 0..6 {
        if let Some(packet) = connection.echo(&[code::WORLD_CITIES, city]).await
            && city == 0
        {
            let city = protocol::decode_city(&packet);
            if !city.is_empty() {
                home_city = Some(city);
            }
        }
    }

    let offset = shared
        .data
        .read()
        .actions
        .time_offset_seconds
        .clamp(-300, 300);
    let target = Local::now() + chrono::Duration::seconds(i64::from(offset));
    connection
        .write(&protocol::encode_time(target), REQUEST_TIMEOUT)
        .await?;
    update_snapshot(shared, watch_id, |snapshot| {
        snapshot.last_time_sync = Some(Utc::now());
        if home_city.is_some() {
            snapshot.home_city = home_city;
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use watchbridge_core::model::AppData;

    #[test]
    fn platform_neutral_uuids_match_the_documented_service() {
        assert_eq!(
            SERVICE_UUID.to_string(),
            "26eb000d-b012-49a8-b1f8-394fb2032b0f"
        );
        assert_ne!(REQUEST_UUID, FEATURES_UUID);
    }

    #[test]
    fn manual_matching_only_claims_a_single_compatible_watch() {
        let mut data = AppData::default();
        data.watches
            .push(SavedWatch::manual("GW-B5600BP-1", "Blue"));
        let matches = data
            .watches
            .iter()
            .filter(|watch| same_watch_family(watch.effective_model(), "GW-B5600"))
            .count();
        assert_eq!(matches, 1);
    }
}
