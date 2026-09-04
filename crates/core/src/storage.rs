use std::fs::{self, File};
use std::io::{self, BufReader, Read, Write};
use std::path::Path;

use atomic_write_file::AtomicWriteFile;

use crate::model::{AppData, SCHEMA_VERSION};

const MAXIMUM_STATE_BYTES: u64 = 10_000_000;

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("the state path has no parent directory")]
    MissingParent,
    #[error("the state file is larger than the 10 MB safety limit")]
    TooLarge,
    #[error("the state path must be a regular file inside a regular directory")]
    UnsafePath,
    #[error("the state was created by a newer WatchBridge version")]
    NewerSchema,
    #[error("could not access the state file: {0}")]
    Io(#[from] io::Error),
    #[error("the state file is not valid JSON: {0}")]
    Json(#[from] serde_json::Error),
}

pub fn load(path: &Path) -> Result<AppData, StorageError> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(AppData::default()),
        Err(error) => return Err(StorageError::Io(error)),
    };
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(StorageError::UnsafePath);
    }
    if metadata.len() > MAXIMUM_STATE_BYTES {
        return Err(StorageError::TooLarge);
    }

    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    BufReader::new(File::open(path)?)
        .take(MAXIMUM_STATE_BYTES + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAXIMUM_STATE_BYTES {
        return Err(StorageError::TooLarge);
    }
    let mut data: AppData = serde_json::from_slice(&bytes)?;
    if data.schema_version > SCHEMA_VERSION {
        return Err(StorageError::NewerSchema);
    }
    data.trim_for_storage();
    Ok(data)
}

pub fn save(path: &Path, data: &AppData) -> Result<(), StorageError> {
    let parent = path.parent().ok_or(StorageError::MissingParent)?;
    fs::create_dir_all(parent)?;
    let parent_metadata = fs::symlink_metadata(parent)?;
    if parent_metadata.file_type().is_symlink() || !parent_metadata.is_dir() {
        return Err(StorageError::UnsafePath);
    }
    if path.exists() {
        let metadata = fs::symlink_metadata(path)?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(StorageError::UnsafePath);
        }
    }

    let mut normalized = data.clone();
    normalized.trim_for_storage();
    let bytes = serde_json::to_vec_pretty(&normalized)?;
    if bytes.len() as u64 > MAXIMUM_STATE_BYTES {
        return Err(StorageError::TooLarge);
    }

    let mut output = AtomicWriteFile::open(path)?;
    output.write_all(&bytes)?;
    output.sync_all()?;
    output.commit()?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_round_trips_atomically() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("state.json");
        let data = AppData::demo();

        save(&path, &data).unwrap();
        let loaded = load(&path).unwrap();

        assert_eq!(loaded.schema_version, data.schema_version);
        assert_eq!(loaded.watches.len(), 1);
        assert!(!path.with_extension("json.tmp").exists());
    }

    #[test]
    fn missing_state_is_a_clean_default() {
        let directory = tempfile::tempdir().unwrap();
        let loaded = load(&directory.path().join("missing.json")).unwrap();
        assert!(loaded.watches.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn symbolic_link_state_files_are_rejected() {
        use std::os::unix::fs::symlink;

        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("target.json");
        fs::write(&target, b"{}").unwrap();
        let linked = directory.path().join("state.json");
        symlink(&target, &linked).unwrap();

        assert!(matches!(load(&linked), Err(StorageError::UnsafePath)));
        assert!(matches!(
            save(&linked, &AppData::default()),
            Err(StorageError::UnsafePath)
        ));
    }
}
