//! Sample-data renderer for visual CI review. No state access, BLE or action callbacks.
use std::cell::RefCell;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

use anyhow::{Context as _, ensure};
use slint::{ComponentHandle as _, LogicalSize, Rgba8Pixel, SharedPixelBuffer, Timer};
use watchbridge_core::keyboard::KeyboardShortcut;
use watchbridge_core::model::{ActionKind, WatchAction, WatchButtonEvent};
use watchbridge_core::modes::ActionLayer;

use super::{MainWindow, install_keyboard_keys, refresh_ui, state::SharedState};

pub fn run(
    ui: MainWindow,
    path: PathBuf,
    keyboard: bool,
    minimum: bool,
    scroll: f32,
) -> anyhow::Result<()> {
    ensure!(
        path.extension().is_some_and(|ext| ext == "bmp"),
        "snapshot path must end in .bmp"
    );
    let state = SharedState::demo();
    {
        let mut data = state.data.write();
        data.actions.switch_event = Some(WatchButtonEvent::Find);
        data.actions.alternate_actions.insert(
            WatchButtonEvent::Time,
            WatchAction {
                kind: ActionKind::Keyboard,
                value: String::new(),
                keyboard: Some(KeyboardShortcut {
                    control: true,
                    repetitions: 2,
                    ..Default::default()
                }),
            },
        );
        data.actions.alternate_actions.insert(
            WatchButtonEvent::Connect,
            WatchAction {
                kind: ActionKind::Speak,
                value: "Time for a break".to_owned(),
                keyboard: None,
            },
        );
    }
    state.runtime.write().editing_layer = ActionLayer::Alternate;
    install_keyboard_keys(&ui);
    refresh_ui(&ui, &state);
    ui.set_selected_navigation(5);
    ui.set_actions_preview_scroll(scroll);
    if keyboard {
        ui.set_keyboard_event("TIME".into());
        ui.set_keyboard_control(true);
        ui.set_keyboard_repetitions(2);
    }
    ui.window().set_size(LogicalSize::new(
        if minimum { 1080.0 } else { 1240.0 },
        if minimum { 700.0 } else { 800.0 },
    ));
    let result = Rc::new(RefCell::new(None));
    let captured = result.clone();
    let weak = ui.as_weak();
    Timer::single_shot(Duration::from_secs(1), move || {
        *captured.borrow_mut() = Some((|| {
            let ui = weak
                .upgrade()
                .context("snapshot window closed before rendering")?;
            let pixels = ui.window().take_snapshot()?;
            ensure!(
                pixels
                    .as_slice()
                    .iter()
                    .filter(|pixel| pixel.r > 96 || pixel.g > 96 || pixel.b > 96)
                    .take(50)
                    .count()
                    == 50,
                "snapshot is blank; refusing to publish an empty layout preview"
            );
            save_bmp(&path, &pixels)
        })());
        let _ = slint::quit_event_loop();
    });
    ui.run()?;
    result
        .borrow_mut()
        .take()
        .context("snapshot timer did not complete")?
}

/// Uncompressed top-down BMP, avoiding a screenshot-only encoding dependency.
/// Export just the Slint client area, not the desktop, native frame or other apps.
fn save_bmp(path: &Path, pixels: &SharedPixelBuffer<Rgba8Pixel>) -> anyhow::Result<()> {
    let (width, height) = (pixels.width(), pixels.height());
    ensure!(
        width > 0 && height > 0 && width <= 8192 && height <= 8192,
        "snapshot dimensions out of bounds"
    );
    let bytes = width * height * 4;
    let mut header = [0u8; 54];
    header[..2].copy_from_slice(b"BM");
    header[2..6].copy_from_slice(&(54 + bytes).to_le_bytes());
    header[10..14].copy_from_slice(&54u32.to_le_bytes());
    header[14..18].copy_from_slice(&40u32.to_le_bytes());
    header[18..22].copy_from_slice(&width.to_le_bytes());
    header[22..26].copy_from_slice(&(-(height as i32)).to_le_bytes());
    header[26..28].copy_from_slice(&1u16.to_le_bytes());
    header[28..30].copy_from_slice(&32u16.to_le_bytes());
    header[34..38].copy_from_slice(&bytes.to_le_bytes());
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)?;
    let mut writer = std::io::BufWriter::new(file);
    writer.write_all(&header)?;
    for pixel in pixels.as_slice() {
        writer.write_all(&[pixel.b, pixel.g, pixel.r, 255])?;
    }
    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn snapshot_encoder_preserves_pixels_and_never_overwrites_a_file() {
        let folder = tempfile::tempdir().unwrap();
        let path = folder.path().join("snapshot.bmp");
        let mut pixels = SharedPixelBuffer::<Rgba8Pixel>::new(1, 1);
        pixels.make_mut_bytes().copy_from_slice(&[10, 20, 30, 255]);
        save_bmp(&path, &pixels).unwrap();
        let original = std::fs::read(&path).unwrap();
        assert_eq!(&original[..2], b"BM");
        assert_eq!(&original[54..], &[30, 20, 10, 255]);
        assert!(save_bmp(&path, &pixels).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), original);
    }
}
