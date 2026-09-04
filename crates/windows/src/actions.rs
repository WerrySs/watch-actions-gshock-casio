use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(target_os = "windows")]
use base64::Engine as _;
use url::Url;

use watchbridge_core::model::{ActionKind, WatchAction, sanitize_single_line};

const PROCESS_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionOutcome {
    pub succeeded: bool,
    pub summary: String,
}

pub async fn run(action: WatchAction) -> ActionOutcome {
    tokio::task::spawn_blocking(move || run_blocking(&action))
        .await
        .unwrap_or_else(|_| ActionOutcome {
            succeeded: false,
            summary: "The action worker stopped unexpectedly".to_owned(),
        })
}

pub fn run_sync(action: &WatchAction) -> ActionOutcome {
    run_blocking(action)
}

fn run_blocking(action: &WatchAction) -> ActionOutcome {
    match action.kind {
        ActionKind::None => success("No action configured"),
        ActionKind::FindComputer => find_computer(),
        ActionKind::Speak => {
            let text = sanitize_single_line(&action.value, 240);
            speak(if text.is_empty() { "Here I am" } else { &text })
        }
        ActionKind::OpenUrl => open_url(&action.value),
        ActionKind::OpenApplication => open_application(&action.value),
        ActionKind::LockScreen => lock_screen(),
        ActionKind::ToggleMute => toggle_mute(),
        ActionKind::PlayPause => play_pause(),
    }
}

fn find_computer() -> ActionOutcome {
    #[cfg(target_os = "macos")]
    for _ in 0..3 {
        let mut command = Command::new("/usr/bin/afplay");
        command.args(["-v", "2", "/System/Library/Sounds/Glass.aiff"]);
        let _ = run_process(command, PROCESS_TIMEOUT);
    }

    #[cfg(target_os = "windows")]
    for _ in 0..3 {
        let _ = run_powershell("[console]::beep(880,250)");
    }

    let speech = speak("Here I am");
    if speech.succeeded {
        success("Played the find-computer alert")
    } else {
        failure("The visual action ran, but the sound could not be played")
    }
}

fn speak(text: &str) -> ActionOutcome {
    let text = sanitize_single_line(text, 240);
    if text.is_empty() {
        return failure("Enter a phrase before running this action");
    }

    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("/usr/bin/say");
        command.arg(text);
        return process_outcome(
            run_process(command, PROCESS_TIMEOUT),
            "Spoke the configured phrase",
        );
    }

    #[cfg(target_os = "windows")]
    {
        let encoded_text = base64::engine::general_purpose::STANDARD.encode(text.as_bytes());
        let script = format!(
            "$t=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{encoded_text}')); Add-Type -AssemblyName System.Speech; $v=New-Object System.Speech.Synthesis.SpeechSynthesizer; $v.Speak($t)"
        );
        return process_outcome(run_powershell(&script), "Spoke the configured phrase");
    }

    #[allow(unreachable_code)]
    failure("Speech is not available on this operating system")
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

fn open_application(value: &str) -> ActionOutcome {
    let value = sanitize_single_line(value, 240);
    if value.is_empty() {
        return failure("Enter an application name or executable path");
    }

    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("/usr/bin/open");
        command.args(["-a", &value]);
        return process_outcome(
            run_process(command, PROCESS_TIMEOUT),
            "Opened the application",
        );
    }

    #[cfg(target_os = "windows")]
    {
        let command = Command::new(value);
        return process_outcome(
            run_process(command, PROCESS_TIMEOUT),
            "Opened the application",
        );
    }

    #[allow(unreachable_code)]
    failure("Opening applications is not available on this operating system")
}

fn lock_screen() -> ActionOutcome {
    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new(
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
        );
        command.arg("-suspend");
        let result = run_process(command, PROCESS_TIMEOUT);
        if result == ProcessResult::Succeeded {
            return success("Locked the screen");
        }
        let mut fallback = Command::new("/usr/bin/pmset");
        fallback.arg("displaysleepnow");
        return process_outcome(run_process(fallback, PROCESS_TIMEOUT), "Locked the screen");
    }

    #[cfg(target_os = "windows")]
    {
        let mut command = Command::new("rundll32.exe");
        command.arg("user32.dll,LockWorkStation");
        return process_outcome(run_process(command, PROCESS_TIMEOUT), "Locked the screen");
    }

    #[allow(unreachable_code)]
    failure("Screen locking is not available on this operating system")
}

fn toggle_mute() -> ActionOutcome {
    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("/usr/bin/osascript");
        command.args([
            "-e",
            "set volume output muted not (output muted of (get volume settings))",
        ]);
        return process_outcome(run_process(command, PROCESS_TIMEOUT), "Toggled mute");
    }

    #[cfg(target_os = "windows")]
    {
        return process_outcome(
            run_powershell("$w=New-Object -ComObject WScript.Shell; $w.SendKeys([char]173)"),
            "Toggled mute",
        );
    }

    #[allow(unreachable_code)]
    failure("Mute control is not available on this operating system")
}

fn play_pause() -> ActionOutcome {
    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("/usr/bin/osascript");
        command.args(["-e", "tell application \"Music\" to playpause"]);
        return process_outcome(
            run_process(command, PROCESS_TIMEOUT),
            "Toggled media playback",
        );
    }

    #[cfg(target_os = "windows")]
    {
        let script = "Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class K { [DllImport(\"user32.dll\")] public static extern void keybd_event(byte a, byte b, uint c, uint d); }'; [K]::keybd_event(0xB3,0,0,0); [K]::keybd_event(0xB3,0,2,0)";
        return process_outcome(run_powershell(script), "Toggled media playback");
    }

    #[allow(unreachable_code)]
    failure("Media control is not available on this operating system")
}

#[cfg(target_os = "windows")]
fn run_powershell(script: &str) -> ProcessResult {
    let utf16: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let encoded = base64::engine::general_purpose::STANDARD.encode(utf16);
    let mut command = Command::new("powershell.exe");
    command.args([
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
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return ProcessResult::TimedOut;
            }
            Err(_) => return ProcessResult::Failed,
        }
    }
}

fn process_outcome(result: ProcessResult, success_message: &str) -> ActionOutcome {
    match result {
        ProcessResult::Succeeded => success(success_message),
        ProcessResult::Failed => failure("The operating system rejected the action"),
        ProcessResult::TimedOut => failure("The action exceeded its 20-second deadline"),
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
        assert!(!open_url("file:///tmp/example").succeeded);
        assert!(!open_url("javascript:alert(1)").succeeded);
        assert!(!open_url("https://").succeeded);
    }

    #[test]
    fn process_deadlines_are_enforced() {
        #[cfg(unix)]
        let command = {
            let mut command = Command::new("/bin/sleep");
            command.arg("5");
            command
        };

        #[cfg(windows)]
        let command = {
            let mut command = Command::new("powershell.exe");
            command.args(["-NoProfile", "-Command", "Start-Sleep -Seconds 5"]);
            command
        };

        assert_eq!(
            run_process(command, Duration::from_millis(50)),
            ProcessResult::TimedOut
        );
    }
}
