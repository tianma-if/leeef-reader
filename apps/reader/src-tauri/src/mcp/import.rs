use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use rmcp::schemars;
use serde::{Deserialize, Serialize};

use crate::db::{self, AppState};

const MAX_BOOK_BYTES: u64 = 128 * 1024 * 1024;

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ImportBookInput {
    /// Absolute path to a local EPUB, TXT, PDF, FB2, MOBI, or AZW3 file (up to 128 MiB).
    path: PathBuf,
    /// Defaults to the filename without its extension.
    title: Option<String>,
    author: Option<String>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct BookImport {
    path: PathBuf,
    name: String,
    title: String,
    author: Option<String>,
    media_type: String,
    sha256: String,
}

impl BookImport {
    pub(super) fn prepare(input: ImportBookInput) -> Result<(Self, String), String> {
        if !input.path.is_absolute() {
            return Err("path must be an absolute local file path".into());
        }
        let name = input
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or("path must include a valid filename")?
            .to_owned();
        let media_type = match input
            .path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref()
        {
            Some("epub") => "application/epub+zip",
            Some("txt") => "text/plain",
            Some("pdf") => "application/pdf",
            Some("fb2") => "application/x-fictionbook+xml",
            Some("mobi") => "application/mobi",
            Some("azw3") => "application/azw3",
            _ => {
                return Err(
                    "unsupported ebook extension; use EPUB, TXT, PDF, FB2, MOBI, or AZW3".into(),
                )
            }
        };
        let path = input.path.canonicalize().map_err(|e| e.to_string())?;
        if path.to_str().is_none() {
            return Err("resolved path must be valid Unicode".into());
        }
        let bytes = read_book(&path)?;
        let title = input
            .title
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| {
                input
                    .path
                    .file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or(&name)
            })
            .to_owned();
        let author = input.author.filter(|author| !author.trim().is_empty());
        let sha256 = db::sha256_hex(&bytes);
        let summary = format!(
            "Import {title:?}{} from {:?} ({} bytes)",
            author
                .as_ref()
                .map(|a| format!(" by {a:?}"))
                .unwrap_or_default(),
            path,
            bytes.len(),
        );
        Ok((
            Self {
                path,
                name,
                title,
                author,
                media_type: media_type.into(),
                sha256,
            },
            summary,
        ))
    }

    pub(super) fn apply(self, state: &AppState) -> Result<String, String> {
        let bytes = read_book(&self.path)?;
        if db::sha256_hex(&bytes) != self.sha256 {
            return Err("ebook file changed after planning; create a new import plan".into());
        }
        db::import_book(
            state,
            &self.name,
            &bytes,
            &self.title,
            self.author.as_deref(),
            &self.media_type,
            None,
        )
        .map(|book| book.id)
    }
}

fn read_book(path: &Path) -> Result<Vec<u8>, String> {
    if !fs::metadata(path).map_err(|e| e.to_string())?.is_file() {
        return Err("path must point to a regular file".into());
    }
    let file = File::open(path).map_err(|e| e.to_string())?;
    let metadata = file.metadata().map_err(|e| e.to_string())?;
    if !metadata.is_file() {
        return Err("path must point to a regular file".into());
    }
    if metadata.len() > MAX_BOOK_BYTES {
        return Err("ebook file exceeds 128 MiB".into());
    }
    let mut bytes = Vec::new();
    file.take(MAX_BOOK_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_BOOK_BYTES {
        return Err("ebook file exceeds 128 MiB".into());
    }
    if bytes.is_empty() {
        return Err("ebook file is empty".into());
    }
    Ok(bytes)
}
