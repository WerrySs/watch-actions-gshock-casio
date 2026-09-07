#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod state;

#[cfg(target_os = "windows")]
mod actions;
#[cfg(target_os = "windows")]
mod bluetooth;

use std::cell::Cell;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context as _, anyhow};
use chrono::Local;
use directories::ProjectDirs;
use slint::{ModelRc, Timer, TimerMode, VecModel};
use state::SharedState;
use watchbridge_core::model::{
    ActionKind, SavedWatch, WatchAction, WatchButtonEvent, WatchSettings, format_duration,
    sanitize_single_line,
};

slint::include_modules!();

fn main() -> anyhow::Result<()> {
    let ui = MainWindow::new().context("could not create the WatchBridge window")?;
    let demo = env_flag("--demo") || env_flag("--smoke-test");
    let state = if demo {
        SharedState::demo()
    } else {
        SharedState::load(application_state_path()?)
    };

    #[cfg(target_os = "windows")]
    let bluetooth = (!demo && state.can_mutate())
        .then(|| bluetooth::BluetoothController::start(Arc::clone(&state)));

    #[cfg(not(target_os = "windows"))]
    state.runtime.write().set(
        watchbridge_core::model::ConnectionPhase::Waiting,
        "The native Windows client is available on Windows",
    );

    install_callbacks(&ui, Arc::clone(&state));

    #[cfg(target_os = "windows")]
    if let Some(bluetooth) = &bluetooth {
        install_bluetooth_callbacks(&ui, bluetooth);
    }

    refresh_ui(&ui, &state);
    if env_flag("--smoke-test") {
        return Ok(());
    }
    let refresh_timer = Timer::default();
    let weak = ui.as_weak();
    let refresh_state = Arc::clone(&state);
    let seen_revision = Rc::new(Cell::new(refresh_state.revision()));
    let seen_update = Rc::new(Cell::new(
        refresh_state.runtime.read().last_update.timestamp_millis(),
    ));
    refresh_timer.start(TimerMode::Repeated, Duration::from_millis(500), move || {
        let revision = refresh_state.revision();
        let update = refresh_state.runtime.read().last_update.timestamp_millis();
        if (revision != seen_revision.get() || update != seen_update.get())
            && let Some(window) = weak.upgrade()
        {
            refresh_ui(&window, &refresh_state);
            seen_revision.set(revision);
            seen_update.set(update);
        }
    });

    ui.show().context("could not show the WatchBridge window")?;

    #[cfg(target_os = "windows")]
    let _ = window_vibrancy::apply_mica(ui.window().window_handle(), Some(true));

    ui.run().context("the WatchBridge event loop stopped")?;

    #[cfg(target_os = "windows")]
    if let Some(bluetooth) = bluetooth {
        bluetooth.send(bluetooth::BluetoothCommand::Shutdown);
    }

    Ok(())
}

fn env_flag(flag: &str) -> bool {
    std::env::args_os().any(|argument| argument == flag)
}

fn application_state_path() -> anyhow::Result<std::path::PathBuf> {
    let project = ProjectDirs::from("io.github", "WerrySs", "WatchBridge").ok_or_else(|| {
        anyhow!("the operating system did not provide an application data directory")
    })?;
    Ok(project.data_local_dir().join("state.json"))
}

fn install_callbacks(ui: &MainWindow, state: Arc<SharedState>) {
    ui.on_link_registration({
        let state = Arc::clone(&state);
        move |manual, physical| {
            if !state.can_mutate() {
                return;
            }
            let linked = state
                .data
                .write()
                .link_registration(manual.as_str(), physical.as_str());
            if linked {
                state.save();
                state.trace(
                    "Linked registration to the selected physical watch; actions remain blocked",
                );
            }
        }
    });
    ui.on_select_navigation({
        let weak = ui.as_weak();
        move |index| {
            if let Some(window) = weak.upgrade() {
                window.set_selected_navigation(index.clamp(0, 7));
            }
        }
    });

    ui.on_register_watch({
        let state = Arc::clone(&state);
        move |model, nickname| {
            if !state.can_mutate() {
                return;
            }
            let model = sanitize_single_line(model.as_str(), 48);
            if !watchbridge_core::model::is_supported_model(&model) {
                state.runtime.write().set(
                    watchbridge_core::model::ConnectionPhase::Error,
                    "Choose a supported GW-B5600 model. Other families are not supported.",
                );
                return;
            }
            let mut watch = SavedWatch::manual(&model, nickname.as_str());
            let mut data = state.data.write();
            if data.watches.len() >= 100 {
                return;
            }
            if data.favorite_watch_id.is_none() {
                data.favorite_watch_id = Some(watch.id.clone());
            }
            data.preferred_model = watch.effective_model().to_owned();
            watch.allows_computer_actions = false;
            data.watches.push(watch);
            drop(data);
            state.save();
            state.trace("Saved a watch before pairing");
        }
    });

    ui.on_make_favorite({
        let state = Arc::clone(&state);
        move |identifier| {
            if !state.can_mutate() {
                return;
            }
            let identifier = identifier.as_str();
            let mut data = state.data.write();
            if data.watches.iter().any(|watch| watch.id == identifier) {
                data.favorite_watch_id = Some(identifier.to_owned());
            }
            drop(data);
            state.save();
        }
    });

    ui.on_toggle_trust({
        let state = Arc::clone(&state);
        move |identifier| {
            if !state.can_mutate() {
                return;
            }
            let mut data = state.data.write();
            if let Some(watch) = data
                .watches
                .iter_mut()
                .find(|watch| watch.id == identifier.as_str())
                && watch.is_linked()
                && !watch.manually_registered
                && watchbridge_core::model::is_supported_model(&watch.detected_model)
            {
                watch.allows_computer_actions = !watch.allows_computer_actions;
            }
            drop(data);
            state.save();
        }
    });

    ui.on_change_action({
        let state = Arc::clone(&state);
        move |code, selected_index, value| {
            if !state.can_mutate() {
                return;
            }
            let Some(event) = event_for_code(code.as_str()) else {
                return;
            };
            let kind = usize::try_from(selected_index)
                .ok()
                .and_then(|index| ActionKind::ALL.get(index))
                .copied()
                .unwrap_or(ActionKind::None);
            let action = WatchAction {
                kind,
                value: if kind.needs_value() {
                    sanitize_single_line(value.as_str(), 240)
                } else {
                    String::new()
                },
            };
            state.data.write().actions.actions.insert(event, action);
            state.save();
        }
    });

    ui.on_change_action_value({
        let state = Arc::clone(&state);
        move |code, value| {
            if !state.can_mutate() {
                return;
            }
            let Some(event) = event_for_code(code.as_str()) else {
                return;
            };
            let mut data = state.data.write();
            let action = data.actions.actions.entry(event).or_default();
            if action.kind.needs_value() {
                action.value = sanitize_single_line(value.as_str(), 240);
            }
            drop(data);
            state.save();
        }
    });

    ui.on_test_action({
        let state = Arc::clone(&state);
        move |code| {
            let Some(event) = event_for_code(code.as_str()) else {
                return;
            };
            let action = state.data.read().actions.action(event);
            if action.kind != ActionKind::None {
                #[cfg(target_os = "windows")]
                {
                    if !state.begin_action() {
                        return;
                    }
                    let state = Arc::clone(&state);
                    let failure_state = Arc::clone(&state);
                    let result = std::thread::Builder::new()
                        .name("watchbridge-action-test".to_owned())
                        .spawn(move || {
                            let outcome = actions::run_sync(&action);
                            state.finish_action(outcome.summary);
                        });
                    if result.is_err() {
                        failure_state.finish_action("Could not start the action worker".to_owned());
                    }
                }
            }
        }
    });
}

#[cfg(target_os = "windows")]
fn install_bluetooth_callbacks(ui: &MainWindow, bluetooth: &bluetooth::BluetoothController) {
    let scan_controller = bluetooth.clone();
    ui.on_scan_now(move || scan_controller.send(bluetooth::BluetoothCommand::ScanNow));

    let disconnect_controller = bluetooth.clone();
    ui.on_disconnect(move || disconnect_controller.send(bluetooth::BluetoothCommand::Disconnect));
}

fn refresh_ui(ui: &MainWindow, shared: &SharedState) {
    let data = shared.data.read().clone();
    let runtime = shared.runtime.read().clone();
    let watch = data.panel_watch();

    ui.set_watch_model(
        watch
            .map(|item| item.effective_model())
            .unwrap_or(&data.preferred_model)
            .into(),
    );
    ui.set_watch_name(
        watch
            .map_or_else(|| "Add or connect a watch".to_owned(), SavedWatch::title)
            .into(),
    );
    ui.set_status_text(if !shared.can_mutate() {
        "Local data is protected. Restore a valid backup and restart.".into()
    } else {
        runtime.message.into()
    });
    ui.set_battery_text(
        watch
            .and_then(|item| item.snapshot.battery_percent)
            .map_or_else(|| "—".to_owned(), |value| format!("{value}%"))
            .into(),
    );
    ui.set_temperature_text(
        watch
            .and_then(|item| item.snapshot.temperature_celsius)
            .map_or_else(|| "—".to_owned(), |value| format!("{value} °C"))
            .into(),
    );
    ui.set_city_text(
        watch
            .and_then(|item| item.snapshot.home_city.as_deref())
            .unwrap_or("—")
            .into(),
    );
    ui.set_timer_text(
        watch
            .and_then(|item| item.snapshot.timer_seconds)
            .map_or_else(|| "—".to_owned(), format_duration)
            .into(),
    );
    ui.set_last_connection_text(
        watch
            .and_then(|item| item.last_seen)
            .map(|date| {
                date.with_timezone(&Local)
                    .format("%d %b %Y · %H:%M")
                    .to_string()
            })
            .unwrap_or_else(|| "Not connected yet".to_owned())
            .into(),
    );
    ui.set_watch_count_text(
        format!(
            "{} saved {}",
            data.watches.len(),
            if data.watches.len() == 1 {
                "watch"
            } else {
                "watches"
            }
        )
        .into(),
    );
    ui.set_history_count_text(format!("{} saved sessions", data.history.len()).into());
    ui.set_last_action_text(
        runtime
            .last_action_result
            .unwrap_or_else(|| "No action has run in this session".to_owned())
            .into(),
    );

    let action_rows = WatchButtonEvent::CONFIGURABLE.map(|event| {
        let action = data.actions.action(event);
        ActionRow {
            code: event.code().into(),
            title: event.title().into(),
            detail: event.instructions().into(),
            action: action.summary().into(),
            kind_index: action_kind_index(action.kind),
            value: action.value.into(),
            needs_value: action.kind.needs_value(),
            hint: action.kind.help().into(),
        }
    });
    ui.set_first_action_rows(ui_model(action_rows[..2].to_vec()));
    ui.set_second_action_rows(ui_model(action_rows[2..].to_vec()));
    ui.set_action_rows(ui_model(action_rows));

    let watch_rows = data
        .watches
        .iter()
        .map(|watch| WatchRow {
            link_target_id: if watch.manually_registered {
                data.watches
                    .iter()
                    .filter(|candidate| {
                        candidate.is_linked()
                            && !candidate.manually_registered
                            && watchbridge_core::model::is_supported_model(
                                &candidate.detected_model,
                            )
                            && watchbridge_core::model::same_watch_family(
                                &candidate.detected_model,
                                watch.effective_model(),
                            )
                    })
                    .max_by_key(|candidate| candidate.last_seen)
                    .map(|candidate| candidate.id.clone())
                    .unwrap_or_default()
                    .into()
            } else {
                "".into()
            },
            id: watch.id.clone().into(),
            name: watch.title().into(),
            model: watch.effective_model().into(),
            detail: watch
                .last_seen
                .map(|date| {
                    format!(
                        "Last connected {} · {} sessions",
                        date.with_timezone(&Local).format("%d %b %Y at %H:%M"),
                        watch.connection_count
                    )
                })
                .unwrap_or_else(|| "Saved locally · waiting for first connection".to_owned())
                .into(),
            favorite: data.favorite_watch_id.as_deref() == Some(&watch.id),
            trusted: watch.allows_computer_actions,
            can_trust: watch.is_linked()
                && !watch.manually_registered
                && watchbridge_core::model::is_supported_model(&watch.detected_model),
        })
        .collect::<Vec<_>>();
    ui.set_watch_rows(ui_model(watch_rows));

    let history_rows = data
        .history
        .iter()
        .take(100)
        .map(|record| HistoryRow {
            when: record
                .date
                .with_timezone(&Local)
                .format("%d %b %Y · %H:%M")
                .to_string()
                .into(),
            title: format!("{} · {}", record.event.code(), record.watch_model).into(),
            detail: format!(
                "Battery {} · Temperature {} · Time {}",
                record
                    .battery_percent
                    .map_or_else(|| "—".to_owned(), |value| format!("{value}%")),
                record
                    .temperature_celsius
                    .map_or_else(|| "—".to_owned(), |value| format!("{value} °C")),
                if record.time_synced {
                    "sent"
                } else {
                    "unchanged"
                }
            )
            .into(),
            outcome: record.outcome.clone().into(),
        })
        .collect::<Vec<_>>();
    ui.set_history_rows(ui_model(history_rows));

    let snapshot = watch.map(|item| &item.snapshot);
    let reminder_rows = snapshot
        .map(|snapshot| snapshot.reminders.as_slice())
        .unwrap_or_default()
        .iter()
        .map(|reminder| ReminderRow {
            slot: format!("{:02}", reminder.slot).into(),
            title: if reminder.title.is_empty() {
                "Empty reminder".into()
            } else {
                reminder.title.clone().into()
            },
            schedule: format!(
                "{} · {} to {}",
                reminder.repeat_mode.label(),
                reminder.start.format("%d %b %Y"),
                reminder.end.format("%d %b %Y")
            )
            .into(),
            enabled: reminder.enabled,
        })
        .collect::<Vec<_>>();
    ui.set_reminder_rows(ui_model(reminder_rows));

    let alarm_rows = snapshot
        .map(|snapshot| snapshot.alarms.as_slice())
        .unwrap_or_default()
        .iter()
        .map(|alarm| AlarmRow {
            number: format!("{:02}", alarm.number).into(),
            time: alarm.time_text().into(),
            detail: if alarm.hourly_chime {
                "Alarm · hourly signal".into()
            } else {
                "Alarm".into()
            },
            enabled: alarm.enabled,
        })
        .collect::<Vec<_>>();
    ui.set_alarm_rows(ui_model(alarm_rows));

    ui.set_settings_rows(ui_model(settings_rows(
        snapshot.and_then(|snapshot| snapshot.settings.as_ref()),
    )));
}

fn settings_rows(settings: Option<&WatchSettings>) -> Vec<SettingRow> {
    let Some(settings) = settings else {
        return vec![SettingRow {
            label: "Saved settings".into(),
            value: "Connect with CNCT to read the watch".into(),
        }];
    };
    vec![
        SettingRow {
            label: "Time format".into(),
            value: if settings.twenty_four_hour {
                "24-hour"
            } else {
                "12-hour"
            }
            .into(),
        },
        SettingRow {
            label: "Button tone".into(),
            value: enabled(settings.button_tone).into(),
        },
        SettingRow {
            label: "Automatic light".into(),
            value: enabled(settings.automatic_light).into(),
        },
        SettingRow {
            label: "Power saving".into(),
            value: enabled(settings.power_saving).into(),
        },
        SettingRow {
            label: "Display language".into(),
            value: WatchSettings::LANGUAGES
                .get(usize::from(settings.language_index))
                .copied()
                .unwrap_or("English")
                .into(),
        },
    ]
}

fn enabled(value: bool) -> &'static str {
    if value { "Enabled" } else { "Disabled" }
}

fn action_kind_index(kind: ActionKind) -> i32 {
    ActionKind::ALL
        .iter()
        .position(|candidate| *candidate == kind)
        .and_then(|index| i32::try_from(index).ok())
        .unwrap_or(0)
}

fn event_for_code(code: &str) -> Option<WatchButtonEvent> {
    WatchButtonEvent::CONFIGURABLE
        .into_iter()
        .find(|event| event.code() == code)
}

fn ui_model<T: Clone + 'static>(values: impl IntoIterator<Item = T>) -> ModelRc<T> {
    ModelRc::new(Rc::new(VecModel::from(
        values.into_iter().collect::<Vec<_>>(),
    )))
}
