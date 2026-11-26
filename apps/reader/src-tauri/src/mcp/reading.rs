use std::collections::HashMap;

use rmcp::schemars;
use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::cfi::position;
use crate::db::{self, AppState, Book, Excerpt, ReadingProgress};
use crate::reading_links::ReadingLink;

use super::content::text_before_locator;

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ExcerptSummary {
    id: String,
    book_id: String,
    book_title: Option<String>,
    chapter_title: Option<String>,
    locator: String,
    quote: String,
    note: Option<String>,
    color: String,
    created_at: String,
    open_url: Option<String>,
}

impl ExcerptSummary {
    fn new(excerpt: Excerpt, book: &Book) -> Self {
        let open_url = if book.is_available_locally && !excerpt.locator.is_empty() {
            ReadingLink::excerpt_url(&excerpt.id)
        } else {
            None
        };
        Self {
            id: excerpt.id,
            book_id: excerpt.book_id,
            book_title: excerpt.book_title,
            chapter_title: excerpt.chapter.map(|chapter| chapter.title),
            locator: excerpt.locator,
            quote: excerpt.quote,
            note: excerpt.note,
            color: excerpt.color,
            created_at: excerpt.created_at,
            open_url,
        }
    }
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadingProgressOutput {
    book_id: String,
    locator: String,
    progress: f64,
    chapter_title: Option<String>,
    page: Option<i64>,
    device_id: String,
    updated_at: String,
    resume_url: Option<String>,
}

impl ReadingProgressOutput {
    pub(super) fn new(progress: ReadingProgress, book: &Book) -> Self {
        let resume_url = if book.is_available_locally && !progress.locator.is_empty() {
            ReadingLink::resume_url(&book.id)
        } else {
            None
        };
        Self {
            book_id: progress.book_id,
            locator: progress.locator,
            progress: progress.progress,
            chapter_title: progress.chapter_title,
            page: progress.page,
            device_id: progress.device_id,
            updated_at: progress.updated_at,
            resume_url,
        }
    }
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ExcerptSearchInput {
    /// Case-insensitive substring to match against the quote or note.
    query: Option<String>,
    /// Alternative substrings. A match on any of the terms is enough.
    queries: Option<Vec<String>>,
    book_id: Option<String>,
    color: Option<String>,
    /// If true, include only excerpts with a non-empty reader note.
    notes_only: Option<bool>,
    /// Inclusive RFC 3339 creation time, with a timezone offset.
    from: Option<String>,
    /// Exclusive RFC 3339 creation time, with a timezone offset.
    to: Option<String>,
    /// Zero-based offset. Use nextOffset from the previous page.
    offset: Option<usize>,
    /// Page size from 1 to 100, defaults to 20.
    limit: Option<usize>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ExcerptSearchOutput {
    excerpts: Vec<ExcerptSummary>,
    next_offset: Option<usize>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadingRecapOutput {
    book_id: Option<String>,
    book_title: Option<String>,
    /// The latest saved location. It can move backwards when the reader revisits a passage.
    progress: Option<ReadingProgressOutput>,
    /// Nearby highlights whose entire selection ends before the saved location starts, in book order.
    excerpts: Vec<ExcerptSummary>,
    /// A short passage before the saved location in its EPUB spine item, if the position can be resolved.
    preceding_text: Option<String>,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadingActivityInput {
    /// Inclusive RFC 3339 timestamp with timezone, e.g. the local start of the previous week.
    from: String,
    /// Exclusive RFC 3339 timestamp with timezone, e.g. the local start of the current week.
    to: String,
    /// Zero-based book offset. Use nextOffset from the previous page.
    offset: Option<usize>,
    /// Book page size from 1 to 100, defaults to 20.
    limit: Option<usize>,
}

#[derive(Default, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ActivityCounts {
    reading_seconds: i64,
    session_count: usize,
    excerpt_count: usize,
    note_count: usize,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookActivity {
    book_id: String,
    title: String,
    author: Option<String>,
    #[serde(flatten)]
    counts: ActivityCounts,
    /// Up to five of the latest excerpts created in the period, notes first.
    excerpts: Vec<ExcerptSummary>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadingActivityOutput {
    from: String,
    to: String,
    books_read: usize,
    #[serde(flatten)]
    totals: ActivityCounts,
    books: Vec<BookActivity>,
    next_offset: Option<usize>,
}

fn required_time(value: &str, field: &str) -> Result<OffsetDateTime, String> {
    OffsetDateTime::parse(value, &Rfc3339)
        .map_err(|_| format!("{field} must be an RFC 3339 timestamp with a timezone"))
}

fn has_note(excerpt: &Excerpt) -> bool {
    excerpt
        .note
        .as_deref()
        .is_some_and(|note| !note.trim().is_empty())
}

fn page<T>(
    results: impl IntoIterator<Item = T>,
    offset: Option<usize>,
    limit: Option<usize>,
) -> Result<(Vec<T>, Option<usize>), String> {
    let offset = offset.unwrap_or(0);
    let limit = limit.unwrap_or(20);
    if !(1..=100).contains(&limit) {
        return Err("limit must be between 1 and 100".into());
    }
    let mut results = results
        .into_iter()
        .skip(offset)
        .take(limit + 1)
        .collect::<Vec<_>>();
    let next_offset = if results.len() > limit {
        results.pop();
        Some(offset + limit)
    } else {
        None
    };
    Ok((results, next_offset))
}

fn visible_books(state: &AppState) -> Result<HashMap<String, Book>, String> {
    Ok(db::list_books(state)?
        .into_iter()
        .map(|book| (book.id.clone(), book))
        .collect())
}

pub(super) fn list_excerpts(
    state: &AppState,
    book_id: Option<&str>,
) -> Result<Vec<ExcerptSummary>, String> {
    let books = visible_books(state)?;
    Ok(db::list_excerpts(state, book_id)?
        .into_iter()
        .filter_map(|excerpt| {
            let book = books.get(&excerpt.book_id)?;
            Some(ExcerptSummary::new(excerpt, book))
        })
        .collect())
}

pub(super) fn search_excerpts(
    state: &AppState,
    input: ExcerptSearchInput,
) -> Result<ExcerptSearchOutput, String> {
    let from = input
        .from
        .as_deref()
        .map(|value| required_time(value, "from"))
        .transpose()?;
    let to = input
        .to
        .as_deref()
        .map(|value| required_time(value, "to"))
        .transpose()?;
    if matches!((from, to), (Some(from), Some(to)) if from >= to) {
        return Err("from must be earlier than to".into());
    }
    let terms: Vec<_> = input
        .query
        .into_iter()
        .chain(input.queries.into_iter().flatten())
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .collect();
    let books = visible_books(state)?;
    let matches = db::list_excerpts(state, input.book_id.as_deref())?
        .into_iter()
        .filter_map(|excerpt| {
            let book = books.get(&excerpt.book_id)?;
            if input.notes_only.unwrap_or(false) && !has_note(&excerpt)
                || input
                    .color
                    .as_ref()
                    .is_some_and(|color| color != &excerpt.color)
            {
                return None;
            }
            if from.is_some() || to.is_some() {
                let created = db::parse_stored_time(&excerpt.created_at)?;
                if from.is_some_and(|from| created < from) || to.is_some_and(|to| created >= to) {
                    return None;
                }
            }
            if !terms.is_empty() {
                let quote = excerpt.quote.to_lowercase();
                let note = excerpt.note.as_deref().unwrap_or_default().to_lowercase();
                if !terms
                    .iter()
                    .any(|term| quote.contains(term) || note.contains(term))
                {
                    return None;
                }
            }
            Some(ExcerptSummary::new(excerpt, book))
        });
    let (excerpts, next_offset) = page(matches, input.offset, input.limit)?;
    Ok(ExcerptSearchOutput {
        excerpts,
        next_offset,
    })
}

pub(super) fn recap(state: &AppState, book_id: Option<&str>) -> Result<ReadingRecapOutput, String> {
    let mut books = db::list_books(state)?.into_iter();
    let book = match book_id {
        Some(id) => Some(
            books
                .find(|book| book.id == id)
                .ok_or("book does not exist")?,
        ),
        None => books.find(|book| {
            book.locator
                .as_ref()
                .is_some_and(|locator| !locator.is_empty())
        }),
    };
    let mut output = ReadingRecapOutput {
        book_id: book.as_ref().map(|book| book.id.clone()),
        book_title: book.as_ref().map(|book| book.title.clone()),
        progress: None,
        excerpts: Vec::new(),
        preceding_text: None,
    };
    let Some(book) = book else { return Ok(output) };
    let Some(progress) = db::find_reading_progress(state, &book.id)? else {
        return Ok(output);
    };
    if let Some(stop) = position(&progress.locator) {
        let mut excerpts: Vec<_> = db::list_excerpts(state, Some(&book.id))?
            .into_iter()
            .filter_map(|excerpt| {
                let anchor = position(&excerpt.locator)?;
                (anchor.start < anchor.end && anchor.end <= stop.start).then_some((anchor, excerpt))
            })
            .collect();
        excerpts.sort_unstable_by(|(left, a), (right, b)| {
            left.cmp(right).then_with(|| a.id.cmp(&b.id))
        });
        let last = excerpts.len().saturating_sub(5);
        output.excerpts = excerpts
            .into_iter()
            .skip(last)
            .map(|(_, excerpt)| ExcerptSummary::new(excerpt, &book))
            .collect();
        if book.media_type == "application/epub+zip" {
            output.preceding_text = book
                .file_path
                .as_deref()
                .and_then(|path| text_before_locator(path, &stop));
        }
    }
    output.progress = Some(ReadingProgressOutput::new(progress, &book));
    Ok(output)
}

pub(super) fn activity(
    state: &AppState,
    input: ReadingActivityInput,
) -> Result<ReadingActivityOutput, String> {
    let from = required_time(&input.from, "from")?;
    let to = required_time(&input.to, "to")?;
    if from >= to {
        return Err("from must be earlier than to".into());
    }
    let mut books = visible_books(state)?;
    let mut totals = ActivityCounts::default();
    let mut counts_by_book =
        HashMap::<String, (ActivityCounts, Vec<(OffsetDateTime, Excerpt)>)>::new();

    for session in db::list_sessions(state)? {
        if !books.contains_key(&session.book_id) {
            continue;
        }
        let (Some(start), Some(end)) = (
            db::parse_stored_time(&session.started_at),
            db::parse_stored_time(&session.ended_at),
        ) else {
            continue;
        };
        let seconds = (end.min(to) - start.max(from))
            .whole_seconds()
            .min(session.duration_seconds);
        if seconds > 0 {
            let (counts, _) = counts_by_book.entry(session.book_id).or_default();
            counts.reading_seconds += seconds;
            counts.session_count += 1;
            totals.reading_seconds += seconds;
            totals.session_count += 1;
        }
    }

    for excerpt in db::list_excerpts(state, None)? {
        if !books.contains_key(&excerpt.book_id) {
            continue;
        }
        let Some(created) = db::parse_stored_time(&excerpt.created_at)
            .filter(|created| *created >= from && *created < to)
        else {
            continue;
        };
        let (counts, excerpts) = counts_by_book.entry(excerpt.book_id.clone()).or_default();
        let note = usize::from(has_note(&excerpt));
        counts.excerpt_count += 1;
        counts.note_count += note;
        totals.excerpt_count += 1;
        totals.note_count += note;
        excerpts.push((created, excerpt));
    }

    let books_read = counts_by_book
        .values()
        .filter(|(counts, _)| counts.reading_seconds > 0)
        .count();
    let mut rows: Vec<_> = counts_by_book.into_iter().collect();
    rows.sort_unstable_by(|(a, (left, _)), (b, (right, _))| {
        right
            .reading_seconds
            .cmp(&left.reading_seconds)
            .then_with(|| books[a].title.cmp(&books[b].title))
            .then_with(|| a.cmp(b))
    });
    let (rows, next_offset) = page(rows, input.offset, input.limit)?;
    let books = rows
        .into_iter()
        .map(|(id, (counts, mut excerpts))| {
            let book = books
                .remove(&id)
                .expect("activity rows reference visible books");
            excerpts.sort_unstable_by(|(a_time, a), (b_time, b)| {
                has_note(b)
                    .cmp(&has_note(a))
                    .then_with(|| b_time.cmp(a_time))
                    .then_with(|| a.id.cmp(&b.id))
            });
            let excerpts = excerpts
                .into_iter()
                .take(5)
                .map(|(_, item)| ExcerptSummary::new(item, &book))
                .collect();
            BookActivity {
                book_id: id,
                title: book.title,
                author: book.author,
                counts,
                excerpts,
            }
        })
        .collect();
    Ok(ReadingActivityOutput {
        from: input.from,
        to: input.to,
        books_read,
        totals,
        books,
        next_offset,
    })
}
