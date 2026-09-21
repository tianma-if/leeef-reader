# EdgeEver 书摘同步约定

Leeef Reader 将每本书的全部可见书摘映射为 EdgeEver 中的一篇笔记。同步复用
`apps/reader/src/notes/exportExcerpts.ts` 的 `BookExcerptDocument` 与
`bookExcerptMarkdown()`，确保手动 Markdown 导出和 EdgeEver 笔记内容一致。

## 身份与幂等性

- 本地映射表 `edgeever_excerpt_notes` 以 Leeef `book_id` 为键，保存 EdgeEver 实例、memo id、revision
  和最后一次成功同步的内容哈希。
- 首次同步通过 `POST /api/v1/memos` 创建笔记，后续通过
  `PATCH /api/v1/memos/{id}` 更新同一篇笔记，不按标题重复创建。
- 更新携带 EdgeEver 的 `expectedRevision`。遇到 `revision_conflict` 时停止覆盖并保留
  本地待同步操作，待重新读取远端版本后处理。
- 删除单条书摘只更新整篇笔记；删除书籍不得自动删除 EdgeEver 笔记。

## 内容

- 标题使用书名；作者和书摘数量写入正文头部。
- 正文使用 Markdown，原文以 blockquote 表示，保留书摘内部换行和空行。
- 笔记按书摘创建时间正序排列，保证相同输入生成确定内容。
- 同步内容哈希未变化时不发送更新。

## 配置与安全

- 用户配置自己的 HTTPS EdgeEver 实例 URL、API Token 和目标笔记本。
- Token 只允许发送到用户配置并确认的实例 origin，不写入日志或同步操作 payload。
- 自动同步使用本地 outbox；离线和网络错误可重试，鉴权失败暂停并提示用户。
- 连接测试读取实例的 memo 与 notebook API。Token 需要 `read:notebooks`、`read:memos`
  和 `write:memos` scope。

## 触发点

书摘创建、修改或删除后立即调度同一 `book_id` 的后台同步任务。同一本书的任务串行执行，
后续任务会根据内容哈希跳过重复推送。手动“立即同步”复用同一同步实现，不另建旁路。
