use std::io::Read;
use std::path::Path;

use regex::Regex;
use std::sync::OnceLock;

static SCRIPT_STYLE: OnceLock<Regex> = OnceLock::new();
static MARKUP: OnceLock<Regex> = OnceLock::new();
static WHITESPACE: OnceLock<Regex> = OnceLock::new();

pub fn extract_book_text(path: &str, media_type: &str) -> Result<String, String> {
    match media_type {
        "text/plain" => {
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            Ok(String::from_utf8_lossy(&bytes).into_owned())
        }
        "application/epub+zip" => extract_epub(path),
        "application/x-fictionbook+xml" => {
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            Ok(strip_markup(&String::from_utf8_lossy(&bytes)))
        }
        other => Err(format!("text extraction is not available for {other}")),
    }
}

fn extract_epub(path: &str) -> Result<String, String> {
    let file = std::fs::File::open(Path::new(path)).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    let mut parts = Vec::new();
    for index in 0..archive.len() {
        let entry = archive.by_index(index).map_err(|e| e.to_string())?;
        let name = entry.name().to_ascii_lowercase();
        if !(name.ends_with(".xhtml") || name.ends_with(".html") || name.ends_with(".htm")) {
            continue;
        }
        let mut bytes = Vec::new();
        entry
            .take(16 << 20)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        let text = strip_markup(&String::from_utf8_lossy(&bytes));
        if !text.is_empty() {
            parts.push(text);
        }
    }
    if parts.is_empty() {
        return Err("EPUB contains no readable XHTML".into());
    }
    Ok(parts.join("\n\n"))
}

fn strip_markup(value: &str) -> String {
    let script_style = SCRIPT_STYLE.get_or_init(|| {
        Regex::new(r"(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>").expect("regex")
    });
    let markup = MARKUP.get_or_init(|| Regex::new(r"(?s)<[^>]+>").expect("regex"));
    let whitespace = WHITESPACE.get_or_init(|| Regex::new(r"\s+").expect("regex"));
    let without_script = script_style.replace_all(value, " ");
    let without_tags = markup.replace_all(&without_script, " ");
    let unescaped = html_unescape(&without_tags);
    whitespace.replace_all(&unescaped, " ").trim().to_string()
}

fn html_unescape(value: &str) -> String {
    value
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
}
