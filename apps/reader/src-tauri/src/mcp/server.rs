use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::extract::{Request, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::Router;
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Json;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{
    Implementation, ListResourceTemplatesResult, ListResourcesResult, PaginatedRequestParams,
    ProtocolVersion, ReadResourceRequestParams, ReadResourceResponse, ReadResourceResult, Resource,
    ResourceContents, ResourceTemplate, ServerCapabilities, ServerConfig,
};
use rmcp::transport::streamable_http_server::session::local::LocalSessionManager;
use rmcp::transport::streamable_http_server::{StreamableHttpServerConfig, StreamableHttpService};
use rmcp::{
    schemars, tool, tool_handler, tool_router, ErrorData as McpError, RoleServer, ServerHandler,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::db::{self, AppState};

use super::content::extract_book_text;

const PLAN_TTL: Duration = Duration::from_secs(300);

#[derive(Clone)]
struct WritePlan {
    action: String,
    payload: serde_json::Value,
    expires_at: Instant,
    confirmation: Option<String>,
    applied: Option<ApplyWriteOutput>,
}

#[derive(Clone)]
pub struct LeeefMcp {
    state: AppState,
    plans: Arc<Mutex<HashMap<String, WritePlan>>>,
    #[allow(dead_code)]
    tool_router: ToolRouter<Self>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct HealthOutput {
    status: String,
    database_connected: bool,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct LibraryStatsOutput {
    books: i64,
    excerpts: i64,
    bookmarks: i64,
    pending_sync_operations: i64,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookSummary {
    id: String,
    title: String,
    author: Option<String>,
    media_type: String,
}

#[derive(Serialize, schemars::JsonSchema)]
struct ListBooksOutput {
    books: Vec<BookSummary>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookDetails {
    id: String,
    sha256: String,
    title: String,
    author: Option<String>,
    description: Option<String>,
    media_type: String,
    rating: Option<f64>,
    available_locally: bool,
    created_at: String,
    updated_at: String,
}

#[derive(Serialize, schemars::JsonSchema)]
struct BookOutput {
    book: BookDetails,
}

#[derive(Serialize, schemars::JsonSchema)]
struct SearchBooksOutput {
    books: Vec<BookDetails>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookContentOutput {
    book_id: String,
    media_type: String,
    content: String,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ExcerptSummary {
    id: String,
    book_id: String,
    locator: String,
    quote: String,
    note: Option<String>,
    color: String,
    created_at: String,
}

#[derive(Serialize, schemars::JsonSchema)]
struct ExcerptsOutput {
    excerpts: Vec<ExcerptSummary>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookmarkSummary {
    id: String,
    book_id: String,
    locator: String,
    title: Option<String>,
    note: Option<String>,
    created_at: String,
}

#[derive(Serialize, schemars::JsonSchema)]
struct BookmarksOutput {
    bookmarks: Vec<BookmarkSummary>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookshelfSummary {
    id: String,
    parent_id: Option<String>,
    name: String,
    sort_order: i64,
    book_ids: Vec<String>,
}

#[derive(Serialize, schemars::JsonSchema)]
struct BookshelvesOutput {
    bookshelves: Vec<BookshelfSummary>,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ReadingProgressOutput {
    book_id: String,
    locator: String,
    progress: f64,
    chapter_title: Option<String>,
    page: Option<i64>,
    device_id: String,
    updated_at: String,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct QueryInput {
    query: Option<String>,
    book_id: Option<String>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookIdInput {
    book_id: String,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct UpdateBookMetadataInput {
    book_id: String,
    title: String,
    author: Option<String>,
    description: Option<String>,
    rating: Option<f64>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct MoveBookInput {
    book_id: String,
    bookshelf_id: String,
    sort_order: Option<i64>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
struct EntityIdInput {
    id: String,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct CreateExcerptInput {
    book_id: String,
    locator: String,
    quote: String,
    note: Option<String>,
    color: Option<String>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct UpdateExcerptInput {
    excerpt_id: String,
    note: Option<String>,
    color: String,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct CreateBookmarkInput {
    book_id: String,
    locator: String,
    title: Option<String>,
    note: Option<String>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct UpdateBookmarkInput {
    bookmark_id: String,
    title: Option<String>,
    note: Option<String>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct CreateBookshelfInput {
    name: String,
    parent_id: Option<String>,
    sort_order: Option<i64>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct RenameBookshelfInput {
    bookshelf_id: String,
    name: String,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct MoveBookshelfInput {
    bookshelf_id: String,
    parent_id: Option<String>,
    sort_order: Option<i64>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct BookshelfMembershipInput {
    bookshelf_id: String,
    book_id: String,
    sort_order: Option<i64>,
}

#[derive(Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct UpdateReadingProgressInput {
    book_id: String,
    locator: String,
    progress: f64,
    chapter_title: Option<String>,
    page: Option<i64>,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ConfirmWriteInput {
    plan_id: String,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ApplyWriteInput {
    plan_id: String,
    confirmation_token: String,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct PlanWriteOutput {
    plan_id: String,
    summary: String,
    expires_at: String,
}

#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ConfirmWriteOutput {
    plan_id: String,
    confirmation_token: String,
}

#[derive(Clone, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ApplyWriteOutput {
    entity_id: String,
    operation_id: String,
    applied: bool,
}

fn err(message: impl Into<String>) -> McpError {
    McpError::invalid_params(message.into(), None)
}

fn token_eq(left: &str, right: &str) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.bytes()
        .zip(right.bytes())
        .fold(0u8, |acc, (a, b)| acc | (a ^ b))
        == 0
}

fn matches_query(haystack: &str, query: &str) -> bool {
    query.trim().is_empty() || haystack.to_lowercase().contains(&query.to_lowercase())
}

impl LeeefMcp {
    pub fn new(state: AppState) -> Self {
        Self {
            state,
            plans: Arc::new(Mutex::new(HashMap::new())),
            tool_router: Self::tool_router(),
        }
    }

    fn book_details(book: &db::Book) -> BookDetails {
        BookDetails {
            id: book.id.clone(),
            sha256: book.sha256.clone(),
            title: book.title.clone(),
            author: book.author.clone(),
            description: book.description.clone(),
            media_type: book.media_type.clone(),
            rating: book.rating,
            available_locally: book.is_available_locally,
            created_at: book.created_at.clone(),
            updated_at: book.updated_at.clone(),
        }
    }

    fn require_book(&self, book_id: &str) -> Result<db::Book, McpError> {
        db::list_books(&self.state)
            .map_err(err)?
            .into_iter()
            .find(|book| book.id == book_id)
            .ok_or_else(|| err("book does not exist"))
    }

    fn queue_plan(
        &self,
        action: &str,
        payload: serde_json::Value,
        summary: String,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        let plan_id = format!("plan-{}", Uuid::new_v4());
        let expires_at = Instant::now() + PLAN_TTL;
        let mut plans = self.plans.lock().map_err(|e| err(e.to_string()))?;
        plans.insert(
            plan_id.clone(),
            WritePlan {
                action: action.to_string(),
                payload,
                expires_at,
                confirmation: None,
                applied: None,
            },
        );
        Ok(Json(PlanWriteOutput {
            plan_id,
            summary,
            expires_at: format!("{}s", PLAN_TTL.as_secs()),
        }))
    }

    fn apply_action(
        &self,
        action: &str,
        payload: &serde_json::Value,
    ) -> Result<(String, String), McpError> {
        match action {
            "update_book_metadata" => {
                let input: UpdateBookMetadataInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::update_book(
                    &self.state,
                    &input.book_id,
                    Some(&input.title),
                    input.author.as_deref(),
                    input.rating,
                    input.description.as_deref(),
                )
                .map_err(err)?;
                Ok((input.book_id, Uuid::new_v4().to_string()))
            }
            "delete_book" => {
                let input: BookIdInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::delete_book(&self.state, &input.book_id).map_err(err)?;
                Ok((input.book_id, Uuid::new_v4().to_string()))
            }
            "create_excerpt" => {
                let input: CreateExcerptInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                let color = input.color.clone().unwrap_or_else(|| "yellow".into());
                let id = db::upsert_excerpt(
                    &self.state,
                    &input.book_id,
                    &input.locator,
                    &input.quote,
                    input.note.as_deref(),
                    &color,
                )
                .map_err(err)?;
                Ok((id, Uuid::new_v4().to_string()))
            }
            "update_excerpt" => {
                let input: UpdateExcerptInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::update_excerpt(
                    &self.state,
                    &input.excerpt_id,
                    input.note.as_deref(),
                    &input.color,
                )
                .map_err(err)?;
                Ok((input.excerpt_id, Uuid::new_v4().to_string()))
            }
            "delete_excerpt" => {
                let input: EntityIdInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::delete_excerpt(&self.state, &input.id).map_err(err)?;
                Ok((input.id, Uuid::new_v4().to_string()))
            }
            "create_bookmark" => {
                let input: CreateBookmarkInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                let id = db::add_bookmark(
                    &self.state,
                    &input.book_id,
                    &input.locator,
                    input.title.as_deref(),
                    input.note.as_deref(),
                )
                .map_err(err)?;
                Ok((id, Uuid::new_v4().to_string()))
            }
            "update_bookmark" => {
                let input: UpdateBookmarkInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::update_bookmark(
                    &self.state,
                    &input.bookmark_id,
                    input.title.as_deref(),
                    input.note.as_deref(),
                )
                .map_err(err)?;
                Ok((input.bookmark_id, Uuid::new_v4().to_string()))
            }
            "delete_bookmark" => {
                let input: EntityIdInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::delete_bookmark(&self.state, &input.id).map_err(err)?;
                Ok((input.id, Uuid::new_v4().to_string()))
            }
            "create_bookshelf" => {
                let input: CreateBookshelfInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                let id = db::create_shelf(
                    &self.state,
                    &input.name,
                    input.parent_id.as_deref(),
                    input.sort_order.unwrap_or(0),
                )
                .map_err(err)?;
                Ok((id, Uuid::new_v4().to_string()))
            }
            "rename_bookshelf" => {
                let input: RenameBookshelfInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::rename_shelf(&self.state, &input.bookshelf_id, &input.name).map_err(err)?;
                Ok((input.bookshelf_id, Uuid::new_v4().to_string()))
            }
            "move_bookshelf" => {
                let input: MoveBookshelfInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::move_shelf(
                    &self.state,
                    &input.bookshelf_id,
                    input.parent_id.as_deref(),
                    input.sort_order.unwrap_or(0),
                )
                .map_err(err)?;
                Ok((input.bookshelf_id, Uuid::new_v4().to_string()))
            }
            "delete_bookshelf" => {
                let input: EntityIdInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::delete_shelf(&self.state, &input.id).map_err(err)?;
                Ok((input.id, Uuid::new_v4().to_string()))
            }
            "add_book_to_bookshelf" => {
                let input: BookshelfMembershipInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::add_book_to_shelf(
                    &self.state,
                    &input.bookshelf_id,
                    &input.book_id,
                    input.sort_order.unwrap_or(0),
                )
                .map_err(err)?;
                Ok((
                    format!("{}--{}", input.bookshelf_id, input.book_id),
                    Uuid::new_v4().to_string(),
                ))
            }
            "remove_book_from_bookshelf" => {
                let input: BookshelfMembershipInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::remove_book_from_shelf(&self.state, &input.bookshelf_id, &input.book_id)
                    .map_err(err)?;
                Ok((
                    format!("{}--{}", input.bookshelf_id, input.book_id),
                    Uuid::new_v4().to_string(),
                ))
            }
            "move_book" => {
                let input: MoveBookInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::move_book_to_shelf(
                    &self.state,
                    &input.book_id,
                    &input.bookshelf_id,
                    input.sort_order.unwrap_or(0),
                )
                .map_err(err)?;
                Ok((
                    format!("{}--{}", input.bookshelf_id, input.book_id),
                    Uuid::new_v4().to_string(),
                ))
            }
            "update_reading_progress" => {
                let input: UpdateReadingProgressInput =
                    serde_json::from_value(payload.clone()).map_err(|e| err(e.to_string()))?;
                db::save_progress(
                    &self.state,
                    &input.book_id,
                    &input.locator,
                    input.progress,
                    input.chapter_title.as_deref(),
                    input.page,
                )
                .map_err(err)?;
                Ok((input.book_id, Uuid::new_v4().to_string()))
            }
            other => Err(err(format!("unsupported write action {other}"))),
        }
    }
}

#[tool_router]
impl LeeefMcp {
    #[tool(description = "Check whether the Leeef MCP server and database bridge are healthy.")]
    fn health(&self) -> Result<Json<HealthOutput>, McpError> {
        let connected = db::library_stats(&self.state).is_ok();
        Ok(Json(HealthOutput {
            status: "ok".into(),
            database_connected: connected,
        }))
    }

    #[tool(description = "Return non-deleted library counts and pending sync operation count.")]
    fn library_stats(&self) -> Result<Json<LibraryStatsOutput>, McpError> {
        let stats = db::library_stats(&self.state).map_err(err)?;
        Ok(Json(LibraryStatsOutput {
            books: stats.books,
            excerpts: stats.excerpts,
            bookmarks: stats.bookmarks,
            pending_sync_operations: stats.pending_sync_operations,
        }))
    }

    #[tool(description = "List the visible books in the Leeef library.")]
    fn list_books(&self) -> Result<Json<ListBooksOutput>, McpError> {
        let books = db::list_books(&self.state)
            .map_err(err)?
            .into_iter()
            .map(|book| BookSummary {
                id: book.id,
                title: book.title,
                author: book.author,
                media_type: book.media_type,
            })
            .collect();
        Ok(Json(ListBooksOutput { books }))
    }

    #[tool(description = "Search visible books by title, author, or description.")]
    fn search_books(
        &self,
        Parameters(input): Parameters<QueryInput>,
    ) -> Result<Json<SearchBooksOutput>, McpError> {
        let query = input.query.unwrap_or_default();
        let books = db::list_books(&self.state)
            .map_err(err)?
            .into_iter()
            .filter(|book| {
                matches_query(
                    &format!(
                        "{} {} {}",
                        book.title,
                        book.author.clone().unwrap_or_default(),
                        book.description.clone().unwrap_or_default()
                    ),
                    &query,
                )
            })
            .map(|book| Self::book_details(&book))
            .collect();
        Ok(Json(SearchBooksOutput { books }))
    }

    #[tool(description = "Get complete metadata for one visible book.")]
    fn get_book(
        &self,
        Parameters(input): Parameters<BookIdInput>,
    ) -> Result<Json<BookOutput>, McpError> {
        let book = self.require_book(&input.book_id)?;
        Ok(Json(BookOutput {
            book: Self::book_details(&book),
        }))
    }

    #[tool(description = "Extract readable text from a locally available TXT, EPUB, or FB2 book.")]
    fn get_book_content(
        &self,
        Parameters(input): Parameters<BookIdInput>,
    ) -> Result<Json<BookContentOutput>, McpError> {
        let book = self.require_book(&input.book_id)?;
        let path = book
            .file_path
            .ok_or_else(|| err("book file is not available locally"))?;
        let content = extract_book_text(&path, &book.media_type).map_err(err)?;
        Ok(Json(BookContentOutput {
            book_id: book.id,
            media_type: book.media_type,
            content,
        }))
    }

    #[tool(description = "List visible excerpts, optionally for one book.")]
    fn list_excerpts(
        &self,
        Parameters(input): Parameters<QueryInput>,
    ) -> Result<Json<ExcerptsOutput>, McpError> {
        Ok(Json(ExcerptsOutput {
            excerpts: self.excerpt_summaries(input.book_id.as_deref(), "")?,
        }))
    }

    #[tool(description = "Search excerpt quotes and notes.")]
    fn search_excerpts(
        &self,
        Parameters(input): Parameters<QueryInput>,
    ) -> Result<Json<ExcerptsOutput>, McpError> {
        Ok(Json(ExcerptsOutput {
            excerpts: self.excerpt_summaries(
                input.book_id.as_deref(),
                input.query.as_deref().unwrap_or(""),
            )?,
        }))
    }

    #[tool(description = "List visible bookmarks, optionally for one book.")]
    fn list_bookmarks(
        &self,
        Parameters(input): Parameters<QueryInput>,
    ) -> Result<Json<BookmarksOutput>, McpError> {
        let bookmarks = db::list_bookmarks(&self.state, input.book_id.as_deref())
            .map_err(err)?
            .into_iter()
            .map(|item| BookmarkSummary {
                id: item.id,
                book_id: item.book_id,
                locator: item.locator,
                title: item.title,
                note: item.note,
                created_at: item.created_at,
            })
            .collect();
        Ok(Json(BookmarksOutput { bookmarks }))
    }

    #[tool(description = "List the bookshelf hierarchy and book membership.")]
    fn list_bookshelves(&self) -> Result<Json<BookshelvesOutput>, McpError> {
        Ok(Json(BookshelvesOutput {
            bookshelves: self.bookshelf_summaries()?,
        }))
    }

    #[tool(description = "Get current reading progress for a book.")]
    fn get_reading_progress(
        &self,
        Parameters(input): Parameters<BookIdInput>,
    ) -> Result<Json<ReadingProgressOutput>, McpError> {
        let item = db::get_reading_progress(&self.state, &input.book_id).map_err(err)?;
        Ok(Json(ReadingProgressOutput {
            book_id: item.book_id,
            locator: item.locator,
            progress: item.progress,
            chapter_title: item.chapter_title,
            page: item.page,
            device_id: item.device_id,
            updated_at: item.updated_at,
        }))
    }

    #[tool(
        description = "Plan a title, author, description, or rating update. Returns a plan that requires confirm_write and apply_write."
    )]
    fn update_book_metadata(
        &self,
        Parameters(input): Parameters<UpdateBookMetadataInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.title.trim().is_empty() {
            return Err(err("bookId and title are required"));
        }
        if let Some(rating) = input.rating {
            if !(0.0..=5.0).contains(&rating) {
                return Err(err("rating must be between 0 and 5"));
            }
        }
        self.require_book(&input.book_id)?;
        let summary = format!("update_book_metadata {}", input.book_id);
        self.queue_plan(
            "update_book_metadata",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan moving a book into a bookshelf. Returns a plan that requires confirm_write and apply_write."
    )]
    fn move_book(
        &self,
        Parameters(input): Parameters<MoveBookInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.bookshelf_id.is_empty() {
            return Err(err("bookId and bookshelfId are required"));
        }
        let summary = format!("move_book {}", input.book_id);
        self.queue_plan(
            "move_book",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan a soft deletion of a book. Returns a plan that requires confirm_write and apply_write."
    )]
    fn delete_book(
        &self,
        Parameters(input): Parameters<BookIdInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() {
            return Err(err("bookId is required"));
        }
        let summary = format!("delete_book {}", input.book_id);
        self.queue_plan(
            "delete_book",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan creating an excerpt. Returns a plan that requires confirm_write and apply_write."
    )]
    fn create_excerpt(
        &self,
        Parameters(mut input): Parameters<CreateExcerptInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.locator.is_empty() || input.quote.trim().is_empty() {
            return Err(err("bookId, locator, and quote are required"));
        }
        self.require_book(&input.book_id)?;
        if input.color.as_ref().map(|c| c.is_empty()).unwrap_or(true) {
            input.color = Some("yellow".into());
        }
        let summary = format!("create_excerpt {}", input.book_id);
        self.queue_plan(
            "create_excerpt",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan updating an excerpt note and color. Returns a plan that requires confirm_write and apply_write."
    )]
    fn update_excerpt(
        &self,
        Parameters(input): Parameters<UpdateExcerptInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.excerpt_id.is_empty() || input.color.is_empty() {
            return Err(err("excerptId and color are required"));
        }
        let summary = format!("update_excerpt {}", input.excerpt_id);
        self.queue_plan(
            "update_excerpt",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan deleting an excerpt. Returns a plan that requires confirm_write and apply_write."
    )]
    fn delete_excerpt(
        &self,
        Parameters(input): Parameters<EntityIdInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.id.is_empty() {
            return Err(err("id is required"));
        }
        let summary = format!("delete_excerpt {}", input.id);
        self.queue_plan(
            "delete_excerpt",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan creating a bookmark. Returns a plan that requires confirm_write and apply_write."
    )]
    fn create_bookmark(
        &self,
        Parameters(input): Parameters<CreateBookmarkInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.locator.is_empty() {
            return Err(err("bookId and locator are required"));
        }
        let summary = format!("create_bookmark {}", input.book_id);
        self.queue_plan(
            "create_bookmark",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan updating a bookmark. Returns a plan that requires confirm_write and apply_write."
    )]
    fn update_bookmark(
        &self,
        Parameters(input): Parameters<UpdateBookmarkInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.bookmark_id.is_empty() {
            return Err(err("bookmarkId is required"));
        }
        let summary = format!("update_bookmark {}", input.bookmark_id);
        self.queue_plan(
            "update_bookmark",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan deleting a bookmark. Returns a plan that requires confirm_write and apply_write."
    )]
    fn delete_bookmark(
        &self,
        Parameters(input): Parameters<EntityIdInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.id.is_empty() {
            return Err(err("id is required"));
        }
        let summary = format!("delete_bookmark {}", input.id);
        self.queue_plan(
            "delete_bookmark",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            summary,
        )
    }

    #[tool(
        description = "Plan creating a bookshelf. Returns a plan that requires confirm_write and apply_write."
    )]
    fn create_bookshelf(
        &self,
        Parameters(input): Parameters<CreateBookshelfInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.name.trim().is_empty() {
            return Err(err("name is required"));
        }
        self.queue_plan(
            "create_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("create_bookshelf {}", input.name),
        )
    }

    #[tool(
        description = "Plan renaming a bookshelf. Returns a plan that requires confirm_write and apply_write."
    )]
    fn rename_bookshelf(
        &self,
        Parameters(input): Parameters<RenameBookshelfInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.bookshelf_id.is_empty() || input.name.trim().is_empty() {
            return Err(err("bookshelfId and name are required"));
        }
        self.queue_plan(
            "rename_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("rename_bookshelf {}", input.bookshelf_id),
        )
    }

    #[tool(
        description = "Plan changing a bookshelf parent and order. Returns a plan that requires confirm_write and apply_write."
    )]
    fn move_bookshelf(
        &self,
        Parameters(input): Parameters<MoveBookshelfInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.bookshelf_id.is_empty() {
            return Err(err("bookshelfId is required"));
        }
        if input.parent_id.as_deref() == Some(input.bookshelf_id.as_str()) {
            return Err(err("a bookshelf cannot contain itself"));
        }
        self.queue_plan(
            "move_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("move_bookshelf {}", input.bookshelf_id),
        )
    }

    #[tool(
        description = "Plan deleting a bookshelf while preserving its books. Returns a plan that requires confirm_write and apply_write."
    )]
    fn delete_bookshelf(
        &self,
        Parameters(input): Parameters<EntityIdInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.id.is_empty() {
            return Err(err("id is required"));
        }
        self.queue_plan(
            "delete_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("delete_bookshelf {}", input.id),
        )
    }

    #[tool(
        description = "Plan adding a book to a bookshelf. Returns a plan that requires confirm_write and apply_write."
    )]
    fn add_book_to_bookshelf(
        &self,
        Parameters(input): Parameters<BookshelfMembershipInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.bookshelf_id.is_empty() {
            return Err(err("bookId and bookshelfId are required"));
        }
        self.queue_plan(
            "add_book_to_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("add_book_to_bookshelf {}", input.book_id),
        )
    }

    #[tool(
        description = "Plan removing a book from a bookshelf. Returns a plan that requires confirm_write and apply_write."
    )]
    fn remove_book_from_bookshelf(
        &self,
        Parameters(input): Parameters<BookshelfMembershipInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty() || input.bookshelf_id.is_empty() {
            return Err(err("bookId and bookshelfId are required"));
        }
        self.queue_plan(
            "remove_book_from_bookshelf",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("remove_book_from_bookshelf {}", input.book_id),
        )
    }

    #[tool(
        description = "Plan updating the current reading location. Returns a plan that requires confirm_write and apply_write."
    )]
    fn update_reading_progress(
        &self,
        Parameters(input): Parameters<UpdateReadingProgressInput>,
    ) -> Result<Json<PlanWriteOutput>, McpError> {
        if input.book_id.is_empty()
            || input.locator.is_empty()
            || !(0.0..=1.0).contains(&input.progress)
        {
            return Err(err(
                "bookId and locator are required; progress must be between 0 and 1",
            ));
        }
        self.queue_plan(
            "update_reading_progress",
            serde_json::to_value(&input).map_err(|e| err(e.to_string()))?,
            format!("update_reading_progress {}", input.book_id),
        )
    }

    #[tool(
        description = "Confirm a previously reviewed write plan and receive a one-time apply token."
    )]
    fn confirm_write(
        &self,
        Parameters(input): Parameters<ConfirmWriteInput>,
    ) -> Result<Json<ConfirmWriteOutput>, McpError> {
        let mut plans = self.plans.lock().map_err(|e| err(e.to_string()))?;
        let plan = plans
            .get_mut(&input.plan_id)
            .filter(|plan| Instant::now() < plan.expires_at)
            .ok_or_else(|| err("write plan is missing or expired"))?;
        let token = format!("confirm-{}", Uuid::new_v4());
        plan.confirmation = Some(token.clone());
        Ok(Json(ConfirmWriteOutput {
            plan_id: input.plan_id,
            confirmation_token: token,
        }))
    }

    #[tool(
        description = "Apply a confirmed one-time write plan, including sync operation and audit event."
    )]
    fn apply_write(
        &self,
        Parameters(input): Parameters<ApplyWriteInput>,
    ) -> Result<Json<ApplyWriteOutput>, McpError> {
        let (action, payload) = {
            let mut plans = self.plans.lock().map_err(|e| err(e.to_string()))?;
            let plan = plans
                .get_mut(&input.plan_id)
                .filter(|plan| Instant::now() < plan.expires_at)
                .ok_or_else(|| err("write plan is missing or expired"))?;
            if plan
                .confirmation
                .as_ref()
                .map(|token| token_eq(token, &input.confirmation_token))
                != Some(true)
            {
                return Err(err("write plan was not confirmed"));
            }
            if let Some(applied) = plan.applied.clone() {
                return Ok(Json(applied));
            }
            (plan.action.clone(), plan.payload.clone())
        };
        let (entity_id, operation_id) = self.apply_action(&action, &payload)?;
        db::audit(
            &self.state,
            &action,
            &json!({"planId": input.plan_id, "entityId": entity_id, "payload": payload}),
            "applied",
        )
        .map_err(err)?;
        let applied = ApplyWriteOutput {
            entity_id,
            operation_id,
            applied: true,
        };
        if let Ok(mut plans) = self.plans.lock() {
            if let Some(plan) = plans.get_mut(&input.plan_id) {
                plan.applied = Some(applied.clone());
            }
        }
        Ok(Json(applied))
    }
}

impl LeeefMcp {
    fn excerpt_summaries(
        &self,
        book_id: Option<&str>,
        query: &str,
    ) -> Result<Vec<ExcerptSummary>, McpError> {
        Ok(db::list_excerpts(&self.state, book_id)
            .map_err(err)?
            .into_iter()
            .filter(|item| {
                matches_query(
                    &format!("{} {}", item.quote, item.note.clone().unwrap_or_default()),
                    query,
                )
            })
            .map(|item| ExcerptSummary {
                id: item.id,
                book_id: item.book_id,
                locator: item.locator,
                quote: item.quote,
                note: item.note,
                color: item.color,
                created_at: item.created_at,
            })
            .collect())
    }

    fn bookshelf_summaries(&self) -> Result<Vec<BookshelfSummary>, McpError> {
        db::list_shelves(&self.state)
            .map_err(err)?
            .into_iter()
            .map(|shelf| {
                Ok(BookshelfSummary {
                    book_ids: db::shelf_book_ids(&self.state, &shelf.id).map_err(err)?,
                    id: shelf.id,
                    parent_id: shelf.parent_id,
                    name: shelf.name,
                    sort_order: shelf.sort_order,
                })
            })
            .collect()
    }

    fn json_resource(uri: &str, value: impl Serialize) -> Result<ReadResourceResponse, McpError> {
        let text = serde_json::to_string_pretty(&value).map_err(|e| err(e.to_string()))?;
        Ok(ReadResourceResult::new(vec![ResourceContents::text(text, uri.to_string())]).into())
    }
}

#[tool_handler]
impl ServerHandler for LeeefMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_resources()
                .build(),
        )
        .with_server_info(Implementation::new("leeef", env!("CARGO_PKG_VERSION")))
        .with_protocol_version(ProtocolVersion::V_2024_11_05)
        .with_instructions(
            "Leeef library MCP. Read tools query the same SQLite database as the reader. Write tools return a plan that must be confirmed and applied.",
        )
    }

    async fn list_resources(
        &self,
        _request: Option<PaginatedRequestParams>,
        _: rmcp::service::RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, McpError> {
        Ok(ListResourcesResult {
            resources: vec![Resource::new("leeef://library", "Leeef library")],
            ..Default::default()
        })
    }

    async fn list_resource_templates(
        &self,
        _request: Option<PaginatedRequestParams>,
        _: rmcp::service::RequestContext<RoleServer>,
    ) -> Result<ListResourceTemplatesResult, McpError> {
        let templates = [
            ("Book metadata", "leeef://books/{bookId}"),
            ("Book content", "leeef://books/{bookId}/content"),
            ("Book excerpts", "leeef://books/{bookId}/excerpts"),
            ("Book bookmarks", "leeef://books/{bookId}/bookmarks"),
            ("Bookshelf", "leeef://bookshelves/{bookshelfId}"),
        ]
        .into_iter()
        .map(|(name, uri)| ResourceTemplate::new(uri, name))
        .collect();
        Ok(ListResourceTemplatesResult {
            resource_templates: templates,
            ..Default::default()
        })
    }

    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        _: rmcp::service::RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, McpError> {
        let uri = request.uri;
        let path = uri
            .strip_prefix("leeef://")
            .ok_or_else(|| err("invalid Leeef resource URI"))?;
        let parts: Vec<&str> = path.split('/').filter(|part| !part.is_empty()).collect();
        match parts.as_slice() {
            ["library"] => {
                let books = db::list_books(&self.state)
                    .map_err(err)?
                    .iter()
                    .map(Self::book_details)
                    .collect::<Vec<_>>();
                Self::json_resource(&uri, SearchBooksOutput { books })
            }
            ["books", book_id] => {
                let book = self.require_book(book_id)?;
                Self::json_resource(&uri, Self::book_details(&book))
            }
            ["books", book_id, "content"] => {
                let book = self.require_book(book_id)?;
                let path = book
                    .file_path
                    .ok_or_else(|| err("book file is not available locally"))?;
                let content = extract_book_text(&path, &book.media_type).map_err(err)?;
                Ok(ReadResourceResult::new(vec![ResourceContents::text(content, uri)]).into())
            }
            ["books", book_id, "excerpts"] => Self::json_resource(
                &uri,
                ExcerptsOutput {
                    excerpts: self.excerpt_summaries(Some(book_id), "")?,
                },
            ),
            ["books", book_id, "bookmarks"] => {
                let bookmarks = db::list_bookmarks(&self.state, Some(book_id))
                    .map_err(err)?
                    .into_iter()
                    .map(|item| BookmarkSummary {
                        id: item.id,
                        book_id: item.book_id,
                        locator: item.locator,
                        title: item.title,
                        note: item.note,
                        created_at: item.created_at,
                    })
                    .collect();
                Self::json_resource(&uri, BookmarksOutput { bookmarks })
            }
            ["bookshelves", shelf_id] => {
                let shelf = self
                    .bookshelf_summaries()?
                    .into_iter()
                    .find(|item| item.id == *shelf_id)
                    .ok_or_else(|| err("bookshelf does not exist"))?;
                Self::json_resource(&uri, shelf)
            }
            _ => Err(err(format!("unknown Leeef resource {uri}"))),
        }
    }
}

#[derive(Clone)]
struct AuthToken(String);

async fn require_bearer(
    State(expected): State<AuthToken>,
    request: Request,
    next: Next,
) -> Response {
    let provided = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    let want = format!("Bearer {}", expected.0);
    if !token_eq(provided, &want) {
        let mut response = (StatusCode::UNAUTHORIZED, "Unauthorized").into_response();
        response
            .headers_mut()
            .insert(header::WWW_AUTHENTICATE, HeaderValue::from_static("Bearer"));
        return response;
    }
    next.run(request).await
}

pub async fn bind_and_serve(
    state: AppState,
    token: String,
    cancel: CancellationToken,
) -> Result<SocketAddr, String> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| e.to_string())?;
    let addr = listener.local_addr().map_err(|e| e.to_string())?;
    let mcp = LeeefMcp::new(state);
    let service = StreamableHttpService::new(
        move || Ok(mcp.clone()),
        LocalSessionManager::default().into(),
        StreamableHttpServerConfig::default()
            .with_json_response(true)
            .with_legacy_session_mode(false)
            .with_cancellation_token(cancel.child_token()),
    );
    let router = Router::new()
        .nest_service("/mcp", service)
        .layer(middleware::from_fn_with_state(
            AuthToken(token),
            require_bearer,
        ));
    let shutdown = cancel.clone();
    tokio::spawn(async move {
        let _ = axum::serve(listener, router)
            .with_graceful_shutdown(async move {
                shutdown.cancelled_owned().await;
            })
            .await;
    });
    Ok(addr)
}
