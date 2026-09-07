use std::os::windows::{ffi::OsStringExt, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use base64::Engine as _;
use url::Url;
use watchbridge_core::model::{ActionKind, WatchAction, sanitize_single_line};

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
