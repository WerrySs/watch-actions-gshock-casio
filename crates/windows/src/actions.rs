use std::os::windows::{ffi::OsStringExt, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use base64::Engine as _;
use url::Url;
use watchbridge_core::keyboard::{KeyboardShortcut, KeyboardStep};
use watchbridge_core::model::{ActionKind, WatchAction, sanitize_single_line};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
use windows_sys::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

const PROCESS_TIMEOUT: Duration = Duration::from_secs(20);
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionOutcome {
    pub succeeded: bool,
    pub summary: String,
}

pub async fn run(action: WatchAction) -> ActionOutcome {
    tokio::task::spawn_blocking(move || run_sync(&action))
        .await
        .unwrap_or_else(|_| failure("The action worker stopped unexpectedly"))
}

pub fn run_sync(action: &WatchAction) -> ActionOutcome {
    match action.kind {
        ActionKind::None => success("No action configured"),
        ActionKind::Keyboard => keyboard(action.keyboard.as_ref()),
        ActionKind::FindComputer => {
            let result = run_powershell(
                "[console]::beep(880,250); [console]::beep(880,250); [console]::beep(880,250)",
            );
            process_outcome(result, "Played the find-computer alert")
        }
        ActionKind::Speak => {
            let value = sanitize_single_line(&action.value, 240);
            let text = if value.is_empty() {
                "Here I am"
            } else {
                &value
            };
            let encoded = base64::engine::general_purpose::STANDARD.encode(text.as_bytes());
            let script = format!(
                "$t=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{encoded}')); Add-Type -AssemblyName System.Speech; $v=New-Object System.Speech.Synthesis.SpeechSynthesizer; $v.Speak($t)"
            );
            process_outcome(run_powershell(&script), "Spoke the configured phrase")
        }
        ActionKind::OpenUrl => open_url(&action.value),
        ActionKind::OpenApplication => open_application(&action.value),
        ActionKind::LockScreen => {
            // No pointers are passed; Windows performs the lock asynchronously.
            if unsafe { windows_sys::Win32::System::Shutdown::LockWorkStation() } != 0 {
                success("Requested screen lock")
            } else {
                failure("Windows could not lock the screen")
            }
        }
        ActionKind::ToggleMute => media_key(0xAD, "Toggled speaker mute"),
        ActionKind::PlayPause => media_key(0xB3, "Toggled media playback"),
    }
}

#[cfg(test)]
fn keyboard_plan(shortcut: &KeyboardShortcut) -> Option<Vec<INPUT>> {
    Some(
        shortcut
            .steps()?
            .iter()
            .flat_map(|step| keyboard_step_plan(step).unwrap_or_default())
            .collect(),
    )
}

fn keyboard_step_plan(step: &KeyboardStep) -> Option<Vec<INPUT>> {
    let key = step.definition()?;
    let mut pressed = Vec::new();
    for (enabled, scan, extended) in [
        (step.modifiers & 1 != 0, 0x1D, false),
        (step.modifiers & 2 != 0, 0x38, false),
        (step.modifiers & 4 != 0, 0x2A, false),
        (step.modifiers & 8 != 0, 0x5B, true),
    ] {
        if enabled {
            pressed.push((scan, extended));
        }
    }
    pressed.push((key.windows_scan, key.extended));
    let mut result: Vec<INPUT> = pressed
        .iter()
        .map(|&(scan, extended)| key_input(scan, extended, false))
        .collect();
    result.extend(
        pressed
            .iter()
            .rev()
            .map(|&(scan, extended)| key_input(scan, extended, true)),
    );
    Some(result)
}

fn key_input(scan: u16, extended: bool, up: bool) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: 0,
                wScan: scan,
                dwFlags: KEYEVENTF_SCANCODE
                    | if extended { KEYEVENTF_EXTENDEDKEY } else { 0 }
                    | if up { KEYEVENTF_KEYUP } else { 0 },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

/// A partial SendInput result is a prefix of the ordered plan. Release only
/// keys pressed by that prefix which have not already received their key-up.
fn pending_key_releases(plan: &[INPUT], sent: usize) -> Vec<INPUT> {
    let mut held = Vec::new();
    for input in plan.iter().take(sent) {
        // All callers pass the keyboard-only plan built above.
        let key = unsafe { input.Anonymous.ki };
        let identity = (key.wScan, key.dwFlags & KEYEVENTF_EXTENDEDKEY != 0);
        if key.dwFlags & KEYEVENTF_KEYUP != 0 {
            if let Some(index) = held.iter().rposition(|k| *k == identity) {
                held.remove(index);
            }
        } else {
            held.push(identity);
        }
    }
    held.into_iter()
        .rev()
        .map(|(scan, extended)| key_input(scan, extended, true))
        .collect()
}

fn keyboard(shortcut: Option<&KeyboardShortcut>) -> ActionOutcome {
    let Some(shortcut) = shortcut else {
        return failure("Configure a keyboard shortcut first");
    };
    let Some(steps) = shortcut.steps() else {
        return failure("Invalid or incomplete keyboard shortcut");
    };
    let Some(plans) = steps
        .iter()
        .map(keyboard_step_plan)
        .collect::<Option<Vec<_>>>()
    else {
        return failure("Could not plan the complete recording");
    };
    // Native input is deliberately not elevated: UIPI and secure desktops remain OS boundaries.
    let target = unsafe { GetForegroundWindow() };
    let mut process_id = 0;
    let target_thread = unsafe { GetWindowThreadProcessId(target, &mut process_id) };
    if target.is_null() || process_id == 0 || process_id == std::process::id() {
        return failure("Focus another application before sending keyboard input");
    }
    for (step, plan) in steps.iter().zip(&plans) {
        if step.delay_ms > 0 {
            thread::sleep(Duration::from_millis(u64::from(step.delay_ms)));
        }
        if unsafe { GetForegroundWindow() } != target {
            return failure("Keyboard stopped: the focused window changed");
        }
        let key = step.definition().expect("validated above");
        let virtual_key = unsafe {
            MapVirtualKeyExW(
                u32::from(key.windows_scan) | if key.extended { 0xE000 } else { 0 },
                MAPVK_VSC_TO_VK_EX,
                GetKeyboardLayout(target_thread),
            )
        };
        if virtual_key == 0 {
            return failure("Windows could not map the configured physical key");
        }
        if [0x10, 0x11, 0x12, 0x5B, 0x5C, virtual_key]
            .iter()
            .any(|&key| unsafe { GetAsyncKeyState(key as i32) } < 0)
        {
            return failure("Keyboard stopped: release held keys and try again");
        }
        let sent = unsafe {
            SendInput(
                plan.len() as u32,
                plan.as_ptr(),
                std::mem::size_of::<INPUT>() as i32,
            )
        };
        if sent != plan.len() as u32 {
            let releases = pending_key_releases(plan, sent as usize);
            if !releases.is_empty() {
                // Best effort only: Windows may also reject the cleanup request.
                unsafe {
                    SendInput(
                        releases.len() as u32,
                        releases.as_ptr(),
                        std::mem::size_of::<INPUT>() as i32,
                    );
                }
            }
            return failure(
                "Windows blocked keyboard input; elevated apps and secure desktops are not supported",
            );
        }
    }
    success("Keyboard request sent; the focused app decides how to handle it")
}

fn media_key(key: u8, message: &str) -> ActionOutcome {
    // The only variable in this fixed script is one of the internal virtual-key constants.
    let script = format!(
        "Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class K {{ [DllImport(\"user32.dll\")] public static extern void keybd_event(byte a, byte b, uint c, uint d); }}'; [K]::keybd_event({key},0,0,0); [K]::keybd_event({key},0,2,0)"
    );
    process_outcome(run_powershell(&script), message)
}

fn open_url(value: &str) -> ActionOutcome {
    let Ok(url) = Url::parse(value.trim()) else {
        return failure("Enter a valid HTTP or HTTPS address");
    };
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return failure("Only HTTP and HTTPS addresses with a host are allowed");
    }
    match open::that_detached(url.as_str()) {
        Ok(()) => success("Opened the web link"),
        Err(_) => failure("The operating system could not open the web link"),
    }
}

fn is_application_path(path: &Path) -> bool {
    path.is_absolute()
        && path
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("exe"))
        && path.is_file()
}

fn open_application(value: &str) -> ActionOutcome {
    let path = Path::new(value.trim());
    if !is_application_path(path) {
        return failure("Enter the full path to an existing .exe application");
    }
    // A launched GUI app owns its lifetime; dropping Child on Windows only closes our handle.
    match launch_application(Command::new(path)) {
        Ok(_) => success("Launched the application"),
        Err(_) => failure("Windows could not launch the application"),
    }
}

fn launch_application(mut command: Command) -> std::io::Result<Child> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

fn system_powershell() -> Option<PathBuf> {
    let mut buffer = [0u16; 32768];
    // GetSystemDirectoryW writes at most the supplied size, excluding its trailing NUL in the result.
    let length = unsafe {
        windows_sys::Win32::System::SystemInformation::GetSystemDirectoryW(
            buffer.as_mut_ptr(),
            buffer.len() as u32,
        )
    } as usize;
    if length == 0 || length >= buffer.len() {
        return None;
    }
    Some(
        PathBuf::from(std::ffi::OsString::from_wide(&buffer[..length]))
            .join("WindowsPowerShell/v1.0/powershell.exe"),
    )
}

fn run_powershell(script: &str) -> ProcessResult {
    let Some(path) = system_powershell() else {
        return ProcessResult::Failed;
    };
    let utf16: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let encoded = base64::engine::general_purpose::STANDARD.encode(utf16);
    let mut command = Command::new(path);
    command.creation_flags(CREATE_NO_WINDOW).args([
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-EncodedCommand",
        &encoded,
    ]);
    run_process(command, PROCESS_TIMEOUT)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ProcessResult {
    Succeeded,
    Failed,
    TimedOut,
}

fn run_process(mut command: Command, timeout: Duration) -> ProcessResult {
    command
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .stdin(Stdio::null());
    let Ok(mut child) = command.spawn() else {
        return ProcessResult::Failed;
    };
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                return if status.success() {
                    ProcessResult::Succeeded
                } else {
                    ProcessResult::Failed
                };
            }
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(40)),
            result => {
                let _ = child.kill();
                let _ = child.wait();
                return if result.is_err() {
                    ProcessResult::Failed
                } else {
                    ProcessResult::TimedOut
                };
            }
        }
    }
}

fn process_outcome(result: ProcessResult, message: &str) -> ActionOutcome {
    match result {
        ProcessResult::Succeeded => success(message),
        ProcessResult::Failed => failure("The operating system rejected the action"),
        ProcessResult::TimedOut => failure("The action helper exceeded its 20-second deadline"),
    }
}
fn success(summary: &str) -> ActionOutcome {
    ActionOutcome {
        succeeded: true,
        summary: summary.to_owned(),
    }
}
fn failure(summary: &str) -> ActionOutcome {
    ActionOutcome {
        succeeded: false,
        summary: summary.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn repeated_modifier_taps_have_distinct_complete_releases() {
        let shortcut = KeyboardShortcut::recorded(vec![
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
        let plan = keyboard_plan(&shortcut).unwrap();
        assert_eq!(plan.len(), 4);
        for (index, input) in plan.iter().enumerate() {
            let key = unsafe { input.Anonymous.ki };
            assert_eq!(key.wScan, 0x5B);
            assert_ne!(key.dwFlags & KEYEVENTF_EXTENDEDKEY, 0);
            assert_eq!(key.dwFlags & KEYEVENTF_KEYUP != 0, index % 2 == 1);
        }
        assert!(pending_key_releases(&plan, 2).is_empty());
        assert_eq!(pending_key_releases(&plan, 3).len(), 1);
    }
    #[test]
    fn partial_keyboard_plans_release_only_keys_they_still_hold() {
        let plan = keyboard_plan(&KeyboardShortcut {
            control: true,
            alt: true,
            shift: true,
            meta: true,
            ..Default::default()
        })
        .unwrap();
        for sent in 0..=plan.len() {
            let releases = pending_key_releases(&plan, sent);
            assert_eq!(releases.len(), sent.min(plan.len() - sent));
            let remaining = releases.len();
            for (release, press) in releases.iter().zip(plan[..remaining].iter().rev()) {
                let (release, press) = unsafe { (release.Anonymous.ki, press.Anonymous.ki) };
                assert_eq!(release.wScan, press.wScan);
                assert_eq!(release.dwFlags, press.dwFlags | KEYEVENTF_KEYUP);
            }
        }
    }
    #[test]
    fn keyboard_plan_pairs_all_downs_with_reverse_releases() {
        let shortcut = KeyboardShortcut {
            control: true,
            alt: true,
            shift: true,
            meta: true,
            repetitions: 1,
            ..Default::default()
        };
        let plan = keyboard_plan(&shortcut).unwrap();
        assert_eq!(plan.len(), 10);
        let scans: Vec<_> = plan
            .iter()
            .map(|input| unsafe { input.Anonymous.ki.wScan })
            .collect();
        assert_eq!(
            scans[..5],
            scans[5..].iter().rev().copied().collect::<Vec<_>>()
        );
        for (index, input) in plan.iter().enumerate() {
            let key = unsafe { input.Anonymous.ki };
            assert_eq!(key.dwFlags & KEYEVENTF_KEYUP != 0, index >= 5);
            assert_ne!(key.dwFlags & KEYEVENTF_SCANCODE, 0);
        }
        assert_ne!(
            unsafe { plan[4].Anonymous.ki.dwFlags } & KEYEVENTF_EXTENDEDKEY,
            0
        );
    }
    #[test]
    fn keyboard_plan_rejects_unbounded_or_unknown_input() {
        assert!(
            keyboard_plan(&KeyboardShortcut {
                repetitions: 0,
                ..Default::default()
            })
            .is_none()
        );
        assert!(
            keyboard_plan(&KeyboardShortcut {
                repetitions: 11,
                ..Default::default()
            })
            .is_none()
        );
        assert!(
            keyboard_plan(&KeyboardShortcut {
                key: "invalid".to_owned(),
                ..Default::default()
            })
            .is_none()
        );
    }
    #[test]
    fn only_http_and_https_links_are_allowed() {
        for url in ["file:///C:/test", "javascript:alert(1)", "https://"] {
            assert!(!open_url(url).succeeded);
        }
    }
    #[test]
    fn only_explicit_existing_executables_are_allowed() {
        assert!(!is_application_path(Path::new("notepad.exe")));
        assert!(!is_application_path(Path::new(r"C:\missing\app.cmd")));
        assert!(!is_application_path(Path::new(r"C:\missing\app.exe")));
        assert!(is_application_path(&system_powershell().unwrap()));
    }
    fn sleeper() -> Command {
        let mut command = Command::new(system_powershell().unwrap());
        command.creation_flags(CREATE_NO_WINDOW).args([
            "-NoProfile",
            "-Command",
            "Start-Sleep -Seconds 30",
        ]);
        command
    }
    #[test]
    fn gui_launch_returns_without_waiting_or_killing() {
        let mut child = launch_application(sleeper()).unwrap();
        let still_running = child.try_wait().unwrap().is_none();
        let _ = child.kill();
        let _ = child.wait();
        assert!(still_running);
    }
    #[test]
    fn helper_deadlines_are_enforced() {
        assert_eq!(
            run_process(sleeper(), Duration::from_millis(50)),
            ProcessResult::TimedOut
        );
    }
}
