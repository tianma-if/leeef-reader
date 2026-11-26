use crate::cfi::position;
use crate::db::{parse_stored_time, Excerpt};
use serde_json::{json, Value};
use std::{cmp::Ordering, ops::Range};
use time::{macros::format_description, UtcOffset};

const HEADING: &str = "书摘";
const SOURCE: &str = "来自 Leeef Reader";
const DIVIDER: &str = "edgeeverMergeDivider";
const MARKDOWN_DIVIDER: &str = "<!-- edgeever:merge-divider -->\n\n---";

pub(super) struct ExcerptNote {
    pub nodes: Vec<Value>,
    pub markdown: String,
    managed_markdown: String,
    pub author: Option<Value>,
}

pub(super) enum LegacyBody {
    Unknown,
    Edited,
    Unchanged,
}

fn text(value: &str) -> Value {
    json!({ "type": "text", "text": value })
}

fn heading(level: u8, value: &str) -> Value {
    json!({ "type": "heading", "attrs": { "level": level }, "content": [text(value)] })
}

fn paragraph(content: Vec<Value>) -> Value {
    if content.is_empty() {
        json!({ "type": "paragraph" })
    } else {
        json!({ "type": "paragraph", "content": content })
    }
}

fn inline_lines(value: &str) -> Vec<Value> {
    let mut content = Vec::new();
    for (index, line) in value.split('\n').enumerate() {
        if index != 0 {
            content.push(json!({ "type": "hardBreak" }));
        }
        if !line.is_empty() {
            content.push(text(line));
        }
    }
    content
}

fn lines(value: &str) -> String {
    value.replace("\r\n", "\n").replace('\r', "\n")
}

fn one_line(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn escape_markdown(value: &str) -> String {
    let mut escaped = String::new();
    for ch in value.chars() {
        if ch.is_ascii_punctuation() {
            escaped.push('\\');
        }
        escaped.push(ch);
    }
    escaped
}

fn excerpt_timestamp(created_at: &str) -> Option<String> {
    let date = parse_stored_time(created_at)?;
    let offset = UtcOffset::local_offset_at(date).ok()?;
    let date = date
        .checked_to_offset(offset)?
        .format(format_description!("[year]-[month]-[day]"))
        .ok()?;
    Some(format!("摘录于 {date}"))
}

impl ExcerptNote {
    pub fn new(author: Option<&str>, excerpts: &[Excerpt]) -> Self {
        let mut ordered: Vec<_> = excerpts
            .iter()
            .map(|excerpt| (position(&excerpt.locator), excerpt))
            .collect();
        ordered.sort_by(|(left_position, left), (right_position, right)| {
            match (left_position, right_position) {
                (Some(left), Some(right)) => left.cmp(right),
                (Some(_), None) => Ordering::Less,
                (None, Some(_)) => Ordering::Greater,
                (None, None) => Ordering::Equal,
            }
            .then_with(|| left.created_at.cmp(&right.created_at))
            .then_with(|| left.id.cmp(&right.id))
        });

        let author = author
            .map(one_line)
            .filter(|value| !value.is_empty())
            .map(|value| format!("作者：{value}"));
        let mut nodes = vec![json!({ "type": DIVIDER }), heading(2, HEADING)];
        let mut markdown = vec![MARKDOWN_DIVIDER.to_owned(), format!("## {HEADING}")];
        let mut previous_chapter = None;
        for (_, excerpt) in ordered {
            let chapter = excerpt
                .chapter
                .as_ref()
                .filter(|chapter| !chapter.title.trim().is_empty());
            let chapter_key = chapter.map(|chapter| chapter.key.as_str());
            if chapter_key != previous_chapter {
                let label = chapter
                    .map(|chapter| one_line(&chapter.title))
                    .unwrap_or_else(|| "未分章".into());
                nodes.push(heading(3, &label));
                markdown.push(format!("### {}", escape_markdown(&label)));
                previous_chapter = chapter_key;
            }

            let quote = lines(&excerpt.quote);
            let quote = quote.trim_matches('\n');
            let mut paragraphs: Vec<_> = quote
                .split("\n\n")
                .map(|section| paragraph(inline_lines(section)))
                .collect();
            let mut quote_lines = quote.split('\n').peekable();
            let mut quoted_markdown = Vec::new();
            while let Some(line) = quote_lines.next() {
                let line = if line.is_empty() {
                    ">".into()
                } else {
                    let hard_break = if quote_lines.peek().is_some_and(|next| !next.is_empty()) {
                        "  "
                    } else {
                        ""
                    };
                    format!("> {}{hard_break}", escape_markdown(line))
                };
                quoted_markdown.push(line);
            }
            if let Some(timestamp) = excerpt_timestamp(&excerpt.created_at) {
                paragraphs.push(paragraph(vec![text(&timestamp)]));
                quoted_markdown.push(">".into());
                quoted_markdown.push(format!("> {timestamp}"));
            }
            nodes.push(json!({ "type": "blockquote", "content": paragraphs }));
            markdown.push(quoted_markdown.join("\n"));

            if let Some(note) = excerpt
                .note
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                let note = lines(note);
                let mut annotation =
                    vec![json!({ "type": "text", "text": "批注", "marks": [{ "type": "bold" }] })];
                annotation.extend(inline_lines(&format!(" {note}")));
                nodes.push(paragraph(annotation));
                markdown.push(format!(
                    "**批注** {}",
                    note.split('\n')
                        .map(escape_markdown)
                        .collect::<Vec<_>>()
                        .join("  \n")
                ));
            }
        }
        nodes.push(paragraph(vec![text(SOURCE)]));
        markdown.push(SOURCE.into());
        nodes.push(json!({ "type": DIVIDER }));
        markdown.push(MARKDOWN_DIVIDER.to_owned());
        let managed_markdown = markdown.join("\n\n");
        let markdown = match &author {
            Some(author) => format!("{}\n\n{managed_markdown}", escape_markdown(author)),
            None => managed_markdown.clone(),
        };
        Self {
            nodes,
            markdown,
            managed_markdown,
            author: author.map(|value| paragraph(vec![text(&value)])),
        }
    }

    pub fn merge(
        &self,
        remote: &Value,
        remote_markdown: &str,
        legacy: LegacyBody,
    ) -> Result<(Value, Option<String>), String> {
        let mut doc = remote.clone();
        let blocks = doc
            .get_mut("content")
            .and_then(Value::as_array_mut)
            .ok_or("EdgeEver 未返回可编辑的笔记正文")?;
        let markdown = if let Some(region) = managed_region(blocks)? {
            blocks.splice(region, self.nodes.iter().cloned());
            let start = format!("{MARKDOWN_DIVIDER}\n\n## {HEADING}\n");
            let end = format!("\n{SOURCE}\n\n{MARKDOWN_DIVIDER}");
            replace_markdown(remote_markdown, &start, &end, &self.managed_markdown)
        } else if matches!(legacy, LegacyBody::Unchanged) {
            *blocks = self.author.iter().chain(&self.nodes).cloned().collect();
            Some(self.markdown.clone())
        } else if let Some(region) = matches!(legacy, LegacyBody::Edited)
            .then(|| legacy_region(blocks))
            .flatten()
        {
            let author = blocks
                .get(region.start + 1)
                .filter(|node| plain_text(node).starts_with("作者："))
                .cloned()
                .or_else(|| self.author.clone());
            let start = format!("# {}\n", plain_text(&blocks[region.start]));
            let end = format!("\n{}", plain_text(&blocks[region.end - 1]));
            let replacement = match &author {
                Some(author) => format!(
                    "{}\n\n{}",
                    escape_markdown(&plain_text(author)),
                    self.managed_markdown
                ),
                None => self.managed_markdown.clone(),
            };
            blocks.splice(region, author.into_iter().chain(self.nodes.iter().cloned()));
            replace_markdown(remote_markdown, &start, &end, &replacement)
        } else {
            // An edited legacy note or a removed boundary is ambiguous.
            // Give the new section its own boundaries without discarding any text.
            blocks.extend(self.nodes.iter().cloned());
            Some(format!("{remote_markdown}\n\n{}", self.managed_markdown))
        };
        Ok((doc, markdown))
    }
}

fn replace_markdown(source: &str, start: &str, end: &str, replacement: &str) -> Option<String> {
    let mut starts = source
        .match_indices(start)
        .filter(|(index, _)| *index == 0 || source.as_bytes()[*index - 1] == b'\n');
    let (left, _) = starts.next()?;
    if starts.next().is_some() {
        return None;
    }
    let mut ends = source[left + start.len()..].match_indices(end);
    let (right, _) = ends.next()?;
    if ends.next().is_some() {
        return None;
    }
    let right = left + start.len() + right + end.len();
    if source
        .as_bytes()
        .get(right)
        .is_some_and(|byte| *byte != b'\n')
    {
        return None;
    }
    Some(format!(
        "{}{replacement}{}",
        &source[..left],
        &source[right..]
    ))
}

fn has_type(node: &Value, kind: &str) -> bool {
    node["type"] == kind
}

fn plain_text(node: &Value) -> String {
    if let Some(text) = node["text"].as_str() {
        return text.to_owned();
    }
    node["content"]
        .as_array()
        .into_iter()
        .flatten()
        .map(plain_text)
        .collect()
}

fn is_heading(node: &Value, level: u8, value: &str) -> bool {
    has_type(node, "heading") && node["attrs"]["level"] == level && plain_text(node) == value
}

fn managed_region(blocks: &[Value]) -> Result<Option<Range<usize>>, String> {
    let mut start = None;
    let mut region = None;
    for (index, block) in blocks.iter().enumerate() {
        if !has_type(block, DIVIDER) {
            continue;
        }
        if let Some(from) = start {
            if index > from + 2
                && has_type(&blocks[index - 1], "paragraph")
                && plain_text(&blocks[index - 1]) == SOURCE
            {
                if region.replace(from..index + 1).is_some() {
                    return Err("EdgeEver 笔记中有多个 Leeef Reader 书摘区".into());
                }
                start = None;
                continue;
            }
        }
        if blocks
            .get(index + 1)
            .is_some_and(|next| is_heading(next, 2, HEADING))
        {
            start = Some(index);
        }
    }
    Ok(region)
}

// The old export has a distinctive signature: a count, numbered headings, a
// quotation, and a dated footer for each excerpt. Everything outside it is kept.
fn legacy_region(blocks: &[Value]) -> Option<Range<usize>> {
    for (start, node) in blocks.iter().enumerate() {
        if !has_type(node, "heading") || node["attrs"]["level"] != 1 {
            continue;
        }
        let mut cursor = start + 1;
        if blocks
            .get(cursor)
            .is_some_and(|node| plain_text(node).starts_with("作者："))
        {
            cursor += 1;
        }
        let Some(count) = blocks.get(cursor).and_then(|node| {
            plain_text(node)
                .strip_prefix("书摘：")?
                .strip_suffix(" 条")?
                .parse::<usize>()
                .ok()
        }) else {
            continue;
        };
        if count > blocks.len() {
            continue;
        }
        cursor += 1;
        for index in 1..=count {
            if !blocks
                .get(cursor)
                .is_some_and(|node| is_heading(node, 2, &format!("书摘 {index}")))
                || !blocks
                    .get(cursor + 1)
                    .is_some_and(|node| has_type(node, "blockquote"))
            {
                return None;
            }
            cursor = (cursor + 2..blocks.len()).find(|&next| {
                has_type(&blocks[next], "paragraph")
                    && plain_text(&blocks[next]).starts_with("— 摘录于 ")
            })? + 1;
        }
        return Some(start..cursor);
    }
    None
}
