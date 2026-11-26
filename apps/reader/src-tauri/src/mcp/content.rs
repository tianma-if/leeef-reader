use std::io::Read;
use std::path::Path;

use regex::Regex;
use roxmltree::{Document, Node};
use std::sync::OnceLock;

use crate::cfi::Position;

static SCRIPT_STYLE: OnceLock<Regex> = OnceLock::new();
static MARKUP: OnceLock<Regex> = OnceLock::new();
static WHITESPACE: OnceLock<Regex> = OnceLock::new();

const MAX_EPUB_XML_BYTES: u64 = 4 * 1024 * 1024;
const MAX_RECAP_CHARS: usize = 1200;

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

// Resolve the saved range's start using its package and document CFIs.
// Unknown anchors return no text, so an unsupported markup layout can't expose later passages.
pub(super) fn text_before_locator(path: &str, position: &Position) -> Option<String> {
    let [package_steps, text_steps] = position.start.as_slice() else {
        return None;
    };
    let mut archive = zip::ZipArchive::new(std::fs::File::open(path).ok()?).ok()?;
    let container = read_xml(&mut archive, "META-INF/container.xml")?;
    let container = Document::parse(&container).ok()?;
    let opf_path = container
        .descendants()
        .find(|node| {
            node.has_tag_name("rootfile")
                && node.attribute("media-type") == Some("application/oebps-package+xml")
        })?
        .attribute("full-path")?;
    let opf = read_xml(&mut archive, opf_path)?;
    let opf = Document::parse(&opf).ok()?;
    let itemref = element_at(opf.root_element(), package_steps)?;
    if !itemref.has_tag_name("itemref")
        || !itemref
            .parent()
            .is_some_and(|node| node.has_tag_name("spine"))
    {
        return None;
    }
    let idref = itemref.attribute("idref")?;
    let href = opf
        .descendants()
        .find(|node| {
            node.has_tag_name("item")
                && node.attribute("id") == Some(idref)
                && node.attribute("media-type") == Some("application/xhtml+xml")
                && node
                    .parent()
                    .is_some_and(|node| node.has_tag_name("manifest"))
        })?
        .attribute("href")?;
    let mut base = tauri::Url::parse("https://book.invalid/").ok()?;
    base.set_path(&format!("/{opf_path}"));
    let chapter_url = base.join(href).ok()?;
    if chapter_url.origin() != base.origin() {
        return None;
    }
    let chapter_path = urlencoding::decode(chapter_url.path().strip_prefix('/')?).ok()?;
    let chapter = read_xml(&mut archive, &chapter_path)?;
    let chapter = Document::parse(&chapter).ok()?;
    preceding_text(&chapter, text_steps)
}

fn read_xml(archive: &mut zip::ZipArchive<std::fs::File>, path: &str) -> Option<String> {
    let file = archive.by_name(path).ok()?;
    let mut bytes = Vec::new();
    file.take(MAX_EPUB_XML_BYTES + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() as u64 > MAX_EPUB_XML_BYTES {
        return None;
    }
    String::from_utf8(bytes).ok()
}

fn element_at<'a, 'input>(
    mut node: Node<'a, 'input>,
    steps: &[(u32, u32)],
) -> Option<Node<'a, 'input>> {
    for &(index, offset) in steps {
        if index == 0 || index % 2 != 0 || offset != 0 {
            return None;
        }
        node = node
            .children()
            .filter(Node::is_element)
            .nth(index as usize / 2 - 1)?;
    }
    Some(node)
}

fn text_at<'a, 'input>(
    parent: Node<'a, 'input>,
    slot: u32,
    mut offset: usize,
) -> Option<(Node<'a, 'input>, usize)> {
    // A CFI counts even steps for elements and groups adjacent text nodes into odd steps.
    let mut elements = 0;
    for node in parent.children() {
        if node.is_element() {
            elements += 1;
        } else if elements == slot {
            let Some(text) = node.text().filter(|_| node.is_text()) else {
                continue;
            };
            for (byte, ch) in text.char_indices() {
                if offset == 0 {
                    return Some((node, byte));
                }
                offset = offset.checked_sub(ch.len_utf16())?;
            }
            if offset == 0 {
                return Some((node, text.len()));
            }
        }
        if elements > slot {
            break;
        }
    }
    None
}

fn preceding_text(chapter: &Document<'_>, steps: &[(u32, u32)]) -> Option<String> {
    let root = chapter.root_element();
    let body = root.children().find(|node| node.has_tag_name("body"))?;
    let (&(index, offset), parents) = steps.split_last()?;
    let (anchor, byte) = if index % 2 == 0 {
        (element_at(root, steps)?, None)
    } else {
        let parent = element_at(root, parents)?;
        let (anchor, byte) = text_at(parent, (index - 1) / 2, offset as usize)?;
        (anchor, Some(byte))
    };
    if !anchor.ancestors().any(|node| node == body) {
        return None;
    }

    let visible = |node: Node<'_, '_>| {
        !node.ancestors().any(|parent| {
            matches!(
                parent.tag_name().name(),
                "script" | "style" | "template" | "noscript"
            ) || parent.has_attribute("hidden")
        })
    };
    let mut text = String::new();
    for node in body.descendants() {
        if node == anchor {
            if let Some(byte) = byte.filter(|_| visible(node)) {
                text.push_str(node.text()?.get(..byte)?);
            }
            break;
        }
        if !visible(node) {
            continue;
        }
        if node.is_text() {
            text.push_str(node.text()?);
        } else if matches!(
            node.tag_name().name(),
            "p" | "div"
                | "br"
                | "li"
                | "blockquote"
                | "section"
                | "h1"
                | "h2"
                | "h3"
                | "h4"
                | "h5"
                | "h6"
        ) {
            text.push(' ');
        }
    }
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let start = text
        .char_indices()
        .rev()
        .nth(MAX_RECAP_CHARS - 1)
        .map_or(0, |(index, _)| index);
    (!text.is_empty()).then(|| text[start..].trim_start().to_string())
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
