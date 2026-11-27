use std::io::{Cursor, Read, Seek};
use std::path::Path;

use roxmltree::Document;
use zip::ZipArchive;

pub(crate) const MEDIA_TYPE: &str = "application/epub+zip";
const PACKAGE_MEDIA_TYPE: &str = "application/oebps-package+xml";
const DC_NS: &str = "http://purl.org/dc/elements/1.1/";
const MAX_XML_BYTES: u64 = 4 * 1024 * 1024;
const MAX_COVER_BYTES: u64 = 16 * 1024 * 1024;

pub(crate) struct Package<'a> {
    archive: ZipArchive<Cursor<&'a [u8]>>,
    title: Option<String>,
    author: Option<String>,
    cover_path: Option<String>,
}

impl<'a> Package<'a> {
    pub(crate) fn open(bytes: &'a [u8], media_type: &str) -> Option<Self> {
        if media_type != MEDIA_TYPE {
            return None;
        }
        let mut archive = ZipArchive::new(Cursor::new(bytes)).ok()?;
        let container = read_xml(&mut archive, "META-INF/container.xml")?;
        let container = Document::parse(&container).ok()?;
        let rootfiles = || {
            container
                .descendants()
                .filter(|node| node.has_tag_name("rootfile"))
        };
        let opf_path = rootfiles()
            .find(|node| node.attribute("media-type") == Some(PACKAGE_MEDIA_TYPE))
            .or_else(|| rootfiles().next())?
            .attribute("full-path")?;
        let opf = read_xml(&mut archive, opf_path)?;
        let opf = Document::parse(&opf).ok()?;
        let package = opf.root_element();
        let metadata = package
            .children()
            .find(|node| node.has_tag_name("metadata"));
        let dc_text = |name| {
            metadata?
                .children()
                .filter(|node| node.has_tag_name((DC_NS, name)))
                .filter_map(|node| node.text().map(str::trim))
                .find(|text| !text.is_empty())
                .map(str::to_owned)
        };
        let legacy_cover_id = metadata
            .and_then(|node| {
                node.children().find(|child| {
                    child.has_tag_name("meta") && child.attribute("name") == Some("cover")
                })
            })
            .and_then(|node| node.attribute("content"));
        let cover_path = package
            .children()
            .find(|node| node.has_tag_name("manifest"))
            .and_then(|manifest| {
                let items = || manifest.children().filter(|node| node.has_tag_name("item"));
                items()
                    .find(|node| {
                        node.attribute("properties").is_some_and(|properties| {
                            properties
                                .split_ascii_whitespace()
                                .any(|p| p == "cover-image")
                        })
                    })
                    .or_else(|| {
                        let id = legacy_cover_id.unwrap_or("cover");
                        items().find(|node| node.attribute("id") == Some(id))
                    })?
                    .attribute("href")
            })
            .and_then(|href| resolve_href(opf_path, href));
        Some(Self {
            archive,
            title: dc_text("title"),
            author: dc_text("creator"),
            cover_path,
        })
    }

    pub(crate) fn cover(&mut self) -> Option<Vec<u8>> {
        let bytes = read_entry(
            &mut self.archive,
            self.cover_path.as_deref()?,
            MAX_COVER_BYTES,
        )?;
        (!bytes.is_empty()).then_some(bytes)
    }
}

pub(crate) fn import_metadata(
    package: Option<&Package<'_>>,
    name: &str,
    title: Option<String>,
    author: Option<String>,
) -> (String, Option<String>) {
    let title = title
        .as_deref()
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .map(str::to_owned)
        .or_else(|| package?.title.clone())
        .unwrap_or_else(|| {
            Path::new(name)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or(name)
                .into()
        });
    let author = author
        .filter(|author| !author.trim().is_empty())
        .or_else(|| package?.author.clone());
    (title, author)
}

pub(crate) fn read_xml(archive: &mut ZipArchive<impl Read + Seek>, path: &str) -> Option<String> {
    String::from_utf8(read_entry(archive, path, MAX_XML_BYTES)?).ok()
}

fn read_entry(
    archive: &mut ZipArchive<impl Read + Seek>,
    path: &str,
    limit: u64,
) -> Option<Vec<u8>> {
    let file = archive.by_name(path).ok()?;
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes).ok()?;
    (bytes.len() as u64 <= limit).then_some(bytes)
}

pub(crate) fn resolve_href(opf_path: &str, href: &str) -> Option<String> {
    let mut base = tauri::Url::parse("https://book.invalid/").ok()?;
    base.set_path(&format!("/{opf_path}"));
    let url = base.join(href).ok()?;
    if url.origin() != base.origin() {
        return None;
    }
    urlencoding::decode(url.path().strip_prefix('/')?)
        .ok()
        .map(|path| path.into_owned())
}
