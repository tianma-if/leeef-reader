use std::sync::Mutex;

use serde::Serialize;
use uuid::Uuid;

use crate::db::{self, AppState, Book};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReadingLink {
    Excerpt(Uuid),
    Resume(Uuid),
}

impl ReadingLink {
    pub fn excerpt_url(id: &str) -> Option<String> {
        let id = Uuid::parse_str(id).ok()?;
        Some(format!("leeef-reader://excerpt/{id}"))
    }

    pub fn resume_url(id: &str) -> Option<String> {
        let id = Uuid::parse_str(id).ok()?;
        Some(format!("leeef-reader://resume/{id}"))
    }

    fn parse(url: &tauri::Url) -> Option<Self> {
        if url.scheme() != "leeef-reader"
            || !url.username().is_empty()
            || url.password().is_some()
            || url.port().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return None;
        }
        let id = Uuid::parse_str(url.path().strip_prefix('/')?).ok()?;
        match url.host_str()? {
            "excerpt" => Some(Self::Excerpt(id)),
            "resume" => Some(Self::Resume(id)),
            _ => None,
        }
    }

    fn resolve(self, state: &AppState) -> Result<ReadingDestination, String> {
        let (book_id, preview_locator) = match self {
            Self::Excerpt(id) => {
                let (book_id, locator) = db::excerpt_location(state, &id.to_string())?;
                (book_id, Some(locator))
            }
            Self::Resume(id) => (id.to_string(), None),
        };
        let book = db::list_books(state)?
            .into_iter()
            .find(|book| book.id == book_id)
            .ok_or("此链接对应的书籍不在书库中")?;
        if !book.is_available_locally {
            return Err("此书的文件尚未同步到本机".into());
        }
        if preview_locator.as_ref().is_some_and(String::is_empty) {
            return Err("此书摘没有可打开的原文位置".into());
        }
        Ok(ReadingDestination {
            book,
            preview_locator,
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingDestination {
    book: Book,
    preview_locator: Option<String>,
}

#[derive(Default)]
pub struct PendingReadingLink(Mutex<Option<ReadingLink>>);

#[tauri::command]
pub fn take_reading_link(
    pending: tauri::State<PendingReadingLink>,
    state: tauri::State<AppState>,
) -> Result<Option<ReadingDestination>, String> {
    let link = pending.0.lock().map_err(|error| error.to_string())?.take();
    link.map(|link| link.resolve(&state)).transpose()
}

#[cfg(desktop)]
pub fn listen(app: &tauri::AppHandle) -> tauri_plugin_deep_link::Result<()> {
    use tauri_plugin_deep_link::DeepLinkExt;

    let handle = app.clone();
    app.deep_link()
        .on_open_url(move |event| show(&handle, &event.urls()));
    if let Some(urls) = app.deep_link().get_current()? {
        show(app, &urls);
    }
    Ok(())
}

#[cfg(desktop)]
fn show(app: &tauri::AppHandle, urls: &[tauri::Url]) {
    use tauri::{Emitter, Manager};

    let Some(link) = urls.iter().rev().find_map(ReadingLink::parse) else {
        return;
    };
    let pending = app.state::<PendingReadingLink>();
    if let Ok(mut slot) = pending.0.lock() {
        *slot = Some(link);
    }
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
        let _ = window.emit("reading-link-opened", ());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_accepts_local_library_targets_without_extra_parameters() {
        let id = Uuid::new_v4();
        for (link, expected) in [
            (
                ReadingLink::excerpt_url(&id.to_string()).unwrap(),
                ReadingLink::Excerpt(id),
            ),
            (
                ReadingLink::resume_url(&id.to_string()).unwrap(),
                ReadingLink::Resume(id),
            ),
        ] {
            assert_eq!(ReadingLink::parse(&link.parse().unwrap()), Some(expected));
            assert_eq!(
                ReadingLink::parse(&format!("{link}?file=/tmp/book").parse().unwrap()),
                None
            );
        }
        assert_eq!(
            ReadingLink::parse(&"leeef-reader://excerpt/not-a-uuid".parse().unwrap()),
            None
        );
    }
}
