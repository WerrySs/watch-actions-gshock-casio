use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use anyhow::{Context as _, bail, ensure};

fn main() -> anyhow::Result<()> {
    let mut arguments = env::args().skip(1);
    let command = arguments.next().unwrap_or_else(|| "help".to_owned());
    match command.as_str() {
        "prepare-macos" => prepare_macos(false),
        "package-macos" => package_macos(arguments.next().as_deref()),
        "help" | "--help" | "-h" => {
            println!(
                "Usage:\n  cargo xtask prepare-macos\n  cargo xtask package-macos [version]\n\nSet WATCHBRIDGE_UNIVERSAL=1 to build a universal macOS app."
            );
            Ok(())
        }
        _ => bail!("unknown xtask command: {command}"),
    }
}

fn workspace_root() -> anyhow::Result<PathBuf> {
    let root = env::current_dir().context("could not find the workspace root")?;
    ensure!(
        root.join("Cargo.toml").is_file() && root.join("apps/macos/Package.swift").is_file(),
        "run xtask from the WatchBridge workspace root"
    );
    Ok(root)
}

fn prepare_macos(universal: bool) -> anyhow::Result<()> {
    ensure!(cfg!(target_os = "macos"), "prepare-macos must run on macOS");
    let root = workspace_root()?;
    let destination = root.join("apps/macos/Libraries/libwatchbridge_core.a");
    let parent = destination
        .parent()
        .context("the generated library path has no parent")?;
    fs::create_dir_all(parent)?;

    if universal {
        for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"] {
            run(
                Command::new("rustup").args(["target", "add", target]),
                &format!("install the Rust {target} target"),
            )?;
            run(
                Command::new("cargo").args([
                    "build",
                    "--locked",
                    "--release",
                    "-p",
                    "watchbridge-core",
                    "--target",
                    target,
                ]),
                &format!("build the Rust core for {target}"),
            )?;
        }
        let arm_library = root.join("target/aarch64-apple-darwin/release/libwatchbridge_core.a");
        let intel_library = root.join("target/x86_64-apple-darwin/release/libwatchbridge_core.a");
        let mut lipo = Command::new("lipo");
        lipo.arg("-create")
            .arg(arm_library)
            .arg(intel_library)
            .arg("-output")
            .arg(&destination);
        run(&mut lipo, "create the universal Rust core")?;
    } else {
        run(
            Command::new("cargo").args([
                "build",
                "--locked",
                "--release",
                "-p",
                "watchbridge-core",
            ]),
            "build the Rust core",
        )?;
        fs::copy(
            root.join("target/release/libwatchbridge_core.a"),
            &destination,
        )?;
    }

    println!("Prepared {}", destination.display());
    Ok(())
}

fn package_macos(requested_version: Option<&str>) -> anyhow::Result<()> {
    ensure!(cfg!(target_os = "macos"), "package-macos must run on macOS");
    let root = workspace_root()?;
    let version = requested_version.unwrap_or(env!("CARGO_PKG_VERSION"));
    let version = version.strip_prefix('v').unwrap_or(version);
    ensure!(
        !version.is_empty()
            && version
                .chars()
                .all(|character| character.is_ascii_alphanumeric()
                    || matches!(character, '.' | '-' | '+')),
        "the release version contains unsupported characters"
    );
    let build_number = env::var("WATCHBRIDGE_BUILD_NUMBER").unwrap_or_else(|_| "1".to_owned());
    ensure!(
        !build_number.is_empty()
            && build_number
                .chars()
                .all(|character| character.is_ascii_digit()),
        "WATCHBRIDGE_BUILD_NUMBER must contain digits only"
    );
    let universal = env::var("WATCHBRIDGE_UNIVERSAL").as_deref() == Ok("1");
    prepare_macos(universal)?;

    let package = root.join("apps/macos");
    let mut swift_build = Command::new("swift");
    swift_build.args([
        "build",
        "--package-path",
        package.to_str().context("the package path is not UTF-8")?,
        "--configuration",
        "release",
    ]);
    if universal {
        swift_build.args(["--arch", "arm64", "--arch", "x86_64"]);
    }
    run(&mut swift_build, "build the macOS client")?;

    let mut bin_path_command = Command::new("swift");
    bin_path_command.args([
        "build",
        "--package-path",
        package.to_str().context("the package path is not UTF-8")?,
        "--configuration",
        "release",
        "--show-bin-path",
    ]);
    if universal {
        bin_path_command.args(["--arch", "arm64", "--arch", "x86_64"]);
    }
    let bin_path = command_text(&mut bin_path_command, "find the Swift release binary")?;
    let binary = PathBuf::from(bin_path).join("WatchBridge");
    ensure!(binary.is_file(), "the Swift release binary was not created");

    let release_root = root.join("dist/macos");
    if release_root.exists() {
        fs::remove_dir_all(&release_root)
            .context("could not replace the macOS release directory")?;
    }
    let app = release_root.join("WatchBridge.app");
    let contents = app.join("Contents");
    let macos = contents.join("MacOS");
    let resources = contents.join("Resources");
    fs::create_dir_all(&macos)?;
    fs::create_dir_all(resources.join("Assets"))?;

    fs::copy(&binary, macos.join("WatchBridge"))?;
    fs::copy(
        package.join("Resources/Info.plist"),
        contents.join("Info.plist"),
    )?;
    fs::copy(
        package.join("Resources/AppIcon.icns"),
        resources.join("AppIcon.icns"),
    )?;
    fs::copy(
        package.join("Resources/PrivacyInfo.xcprivacy"),
        resources.join("PrivacyInfo.xcprivacy"),
    )?;
    fs::copy(root.join("LICENSE"), resources.join("LICENSE.txt"))?;
    fs::copy(
        root.join("THIRD_PARTY_NOTICES.md"),
        resources.join("THIRD_PARTY_NOTICES.md"),
    )?;
    copy_directory(&package.join("Resources/Assets"), &resources.join("Assets"))?;

    let plist = contents.join("Info.plist");
    let mut set_version = Command::new("/usr/libexec/PlistBuddy");
    set_version
        .args(["-c", &format!("Set :CFBundleShortVersionString {version}")])
        .arg(&plist);
    run(&mut set_version, "set the app version")?;
    let mut set_build = Command::new("/usr/libexec/PlistBuddy");
    set_build
        .args(["-c", &format!("Set :CFBundleVersion {build_number}")])
        .arg(&plist);
    run(&mut set_build, "set the app build number")?;

    let identity = env::var("WATCHBRIDGE_SIGNING_IDENTITY").unwrap_or_else(|_| "-".to_owned());
    let mut codesign = Command::new("codesign");
    codesign.args(["--force", "--deep", "--options", "runtime"]);
    if identity != "-" {
        codesign.arg("--timestamp");
    }
    codesign
        .arg("--entitlements")
        .arg(package.join("Resources/WatchBridge.entitlements"))
        .arg("--sign")
        .arg(OsStr::new(&identity))
        .arg(&app);
    run(&mut codesign, "sign the macOS app")?;
    let mut verify_signature = Command::new("codesign");
    verify_signature
        .args(["--verify", "--deep", "--strict"])
        .arg(&app);
    run(&mut verify_signature, "verify the macOS signature")?;

    let architecture = if universal {
        "universal"
    } else if env::consts::ARCH == "aarch64" {
        "arm64"
    } else {
        env::consts::ARCH
    };
    let zip = release_root.join(format!("WatchBridge-v{version}-macOS-{architecture}.zip"));
    let mut create_zip = Command::new("ditto");
    create_zip
        .args(["-c", "-k", "--sequesterRsrc", "--keepParent"])
        .arg(&app)
        .arg(&zip);
    run(&mut create_zip, "create the macOS ZIP")?;
    let dmg = release_root.join(format!("WatchBridge-v{version}-macOS-{architecture}.dmg"));
    let mut create_dmg = Command::new("hdiutil");
    create_dmg
        .args(["create", "-volname", "WatchBridge", "-srcfolder"])
        .arg(&app)
        .args(["-ov", "-format", "UDZO"])
        .arg(&dmg);
    run(&mut create_dmg, "create the macOS disk image")?;

    let checksum = release_root.join(format!("WatchBridge-v{version}-macOS.sha256"));
    let mut lines = Vec::new();
    for artifact in [&zip, &dmg] {
        let mut shasum = Command::new("shasum");
        shasum.args(["-a", "256"]).arg(artifact);
        let output = command_text(&mut shasum, "calculate a release checksum")?;
        let hash = output
            .split_whitespace()
            .next()
            .context("shasum returned no checksum")?;
        let filename = artifact
            .file_name()
            .and_then(OsStr::to_str)
            .context("the artifact filename is not UTF-8")?;
        lines.push(format!("{hash}  {filename}"));
    }
    fs::write(&checksum, format!("{}\n", lines.join("\n")))?;

    println!("Packaged {}", app.display());
    println!("Created {}", zip.display());
    println!("Created {}", dmg.display());
    println!("Created {}", checksum.display());
    Ok(())
}

fn copy_directory(source: &Path, destination: &Path) -> anyhow::Result<()> {
    ensure!(source.is_dir(), "{} is not a directory", source.display());
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let target = destination.join(entry.file_name());
        if file_type.is_dir() {
            copy_directory(&entry.path(), &target)?;
        } else if file_type.is_file() {
            fs::copy(entry.path(), target)?;
        } else {
            bail!("release resources cannot contain symbolic links or special files");
        }
    }
    Ok(())
}

fn run(command: &mut Command, purpose: &str) -> anyhow::Result<()> {
    let status = command
        .status()
        .with_context(|| format!("could not {purpose}"))?;
    ensure!(
        status.success(),
        "could not {purpose}: process exited with {status}"
    );
    Ok(())
}

fn command_text(command: &mut Command, purpose: &str) -> anyhow::Result<String> {
    let Output {
        status,
        stdout,
        stderr,
    } = command
        .output()
        .with_context(|| format!("could not {purpose}"))?;
    ensure!(
        status.success(),
        "could not {purpose}: {}",
        String::from_utf8_lossy(&stderr).trim()
    );
    Ok(String::from_utf8(stdout)?.trim().to_owned())
}
