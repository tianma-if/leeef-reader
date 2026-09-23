import { invoke } from '@tauri-apps/api/core'
import { useEffect, useMemo, useRef, useState } from 'react'
import {
  BookOpen,
  Check,
  FolderPlus,
  LayoutGrid,
  List as ListIcon,
  MoreVertical,
  Plus,
  SlidersHorizontal,
  Tag as TagIcon,
  Trash2,
} from 'lucide-react'
import { toast } from 'sonner'
import { api, isAndroid, isMobile, type Book, type Shelf, type Tag } from '../api'
import { prepareBookFile } from '../lib/bookFile'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { CoverImage } from './CoverImage'
import { useLibraryRefresh } from '../lib/useLibraryRefresh'
import { importBatch, type ImportFailure } from './importBatch'

type Props = {
  onOpen: (book: Book) => void
}

const ACCEPT = '.epub,.txt,.mobi,.azw3,.fb2,.pdf,application/epub+zip,text/plain,application/pdf'

type SortKey = 'updated' | 'title' | 'author' | 'progress' | 'created'
type FilterKey = 'all' | 'unread' | 'reading' | 'done'
type ViewMode = 'grid' | 'list'

const decodeBase64 = (data: string) => {
  const binary = atob(data)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes
}

export function LibraryScreen({ onOpen }: Props) {
  const [books, setBooks] = useState<Book[]>([])
  const [tags, setTags] = useState<Tag[]>([])
  const [shelves, setShelves] = useState<Shelf[]>([])
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<SortKey>('updated')
  const [filter, setFilter] = useState<FilterKey>('all')
  const [tag, setTag] = useState('all')
  const [filtersOpen, setFiltersOpen] = useState(false)
  const filtersActive = filter !== 'all' || sort !== 'updated' || tag !== 'all'
  const [busy, setBusy] = useState(false)
  const importing = useRef(false)
  const [importProgress, setImportProgress] = useState({ completed: 0, total: 0 })
  const [importFailures, setImportFailures] = useState<ImportFailure<File>[]>([])
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    return (localStorage.getItem('leeef_library_view') as ViewMode) || 'grid'
  })
  const [editing, setEditing] = useState<Book | null>(null)
  const [selecting, setSelecting] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())

  // Dialog states replacing window.prompt & window.confirm
  const [newShelfOpen, setNewShelfOpen] = useState(false)
  const [newShelfName, setNewShelfName] = useState('')
  const [newTagOpen, setNewTagOpen] = useState(false)
  const [newTagName, setNewTagName] = useState('')
  const [deleteConfirmTarget, setDeleteConfirmTarget] = useState<Book | 'batch' | null>(null)

  const desktop = !isMobile()

  const setViewModeAndSave = (mode: ViewMode) => {
    setViewMode(mode)
    localStorage.setItem('leeef_library_view', mode)
  }

  const reload = async () => {
    const [nextBooks, nextTags, nextShelves] = await Promise.all([
      api.listBooks(),
      api.listTags(),
      api.listShelves(),
    ])
    setBooks(nextBooks)
    setTags(nextTags)
    setShelves(nextShelves)
    setEditing((current) => {
      if (!current) return current
      return nextBooks.find((book) => book.id === current.id) ?? current
    })
  }

  useEffect(() => {
    void reload().catch((cause) => toast.error(String(cause)))
  }, [])

  useLibraryRefresh(reload)

  const importPicked = async (files: File[]) => {
    if (!files.length || importing.current) return
    importing.current = true
    setBusy(true)
    setImportFailures([])
    setImportProgress({ completed: 0, total: files.length })
    try {
      const result = await importBatch(files, async (file) => {
        const source = new Uint8Array(await file.arrayBuffer())
        const prepared = prepareBookFile(file, source)
        await api.importBook({
          name: prepared.name,
          data: prepared.bytes,
          title: prepared.title,
          author: prepared.author,
          mediaType: prepared.mediaType,
          cover: prepared.cover,
        })
      }, (completed) => setImportProgress({ completed, total: files.length }))
      setImportFailures(result.failures)
      if (result.failures.length) {
        toast.error(`导入完成：成功 ${result.succeeded} 本，失败 ${result.failures.length} 本`)
      } else {
        toast.success(`已导入 ${result.succeeded} 本书`)
      }
      await reload().catch((cause) => toast.error(`导入结果已保存，刷新书架失败：${String(cause)}`))
    } catch (cause) {
      toast.error(String(cause))
    } finally {
      importing.current = false
      setBusy(false)
    }
  }

  const onAndroidImport = async () => {
    setBusy(true)
    try {
      const picked = await invoke<{ name: string; data: string }[]>(
        'plugin:native-bridge|pick_books',
      )
      const files = (picked ?? []).map(
        (item) => new File([new Blob([decodeBase64(item.data)])], item.name),
      )
      if (!files.length) setBusy(false)
      await importPicked(files)
    } catch (cause) {
      setBusy(false)
      toast.error(String(cause))
    }
  }

  const visible = useMemo(() => {
    let next = books.filter((book) => {
      const hay = `${book.title} ${book.author ?? ''}`.toLowerCase()
      if (query && !hay.includes(query.toLowerCase())) return false
      if (tag !== 'all' && !book.tags.includes(tag)) return false
      if (filter === 'unread') return book.progress < 0.01
      if (filter === 'reading') return book.progress >= 0.01 && book.progress < 0.999
      if (filter === 'done') return book.progress >= 0.999
      return true
    })
    next = [...next].sort((a, b) => {
      if (sort === 'title') return a.title.localeCompare(b.title, 'zh')
      if (sort === 'author') return (a.author ?? '').localeCompare(b.author ?? '', 'zh')
      if (sort === 'progress') return b.progress - a.progress
      if (sort === 'created') return b.createdAt.localeCompare(a.createdAt)
      return 0
    })
    return next
  }, [books, query, sort, filter, tag])

  const groups = useMemo(() => {
    const used = new Set<string>()
    const sections = shelves
      .map((shelf) => ({
        id: shelf.id,
        name: shelf.name,
        books: visible.filter((book) => book.shelfIds.includes(shelf.id)),
      }))
      .filter((section) => {
        section.books.forEach((book) => used.add(book.id))
        return section.books.length > 0
      })
    const rest = visible.filter((book) => !used.has(book.id))
    if (rest.length) sections.push({ id: 'ungrouped', name: '未分类', books: rest })
    if (!sections.length && visible.length) {
      return [{ id: 'all', name: '', books: visible }]
    }
    return sections
  }, [shelves, visible])

  const toggleSelected = (id: string) => {
    setSelected((current) => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const handleCreateShelf = async () => {
    const trimmed = newShelfName.trim()
    if (!trimmed) return
    try {
      await api.createShelf(trimmed)
      setNewShelfName('')
      setNewShelfOpen(false)
      await reload()
      toast.success('目录创建成功')
    } catch (e) {
      toast.error(String(e))
    }
  }

  const handleCreateTag = async () => {
    const trimmed = newTagName.trim()
    if (!trimmed) return
    try {
      await api.createTag(trimmed, 0x3d4a3c)
      setNewTagName('')
      setNewTagOpen(false)
      await reload()
      toast.success('标签创建成功')
    } catch (e) {
      toast.error(String(e))
    }
  }

  const handleDeleteConfirmed = async () => {
    if (deleteConfirmTarget === 'batch') {
      try {
        await Promise.all([...selected].map((id) => api.deleteBook(id)))
        setSelected(new Set())
        setDeleteConfirmTarget(null)
        await reload()
        toast.success('已删除选中书籍')
      } catch (e) {
        toast.error(String(e))
      }
    } else if (deleteConfirmTarget) {
      try {
        await api.deleteBook(deleteConfirmTarget.id)
        if (editing?.id === deleteConfirmTarget.id) setEditing(null)
        setDeleteConfirmTarget(null)
        await reload()
        toast.success('已删除')
      } catch (e) {
        toast.error(String(e))
      }
    }
  }

  const importButton = isAndroid() ? (
    <Button disabled={busy} onClick={() => void onAndroidImport()}>
      <Plus className="size-4" />
      {busy ? '导入中…' : '导入'}
    </Button>
  ) : (
    <Button asChild disabled={busy}>
      <label>
        <Plus className="size-4" />
        {busy ? '导入中…' : '导入'}
        <input
          hidden
          type="file"
          accept={ACCEPT}
          multiple
          disabled={busy}
          onChange={(event) => {
            const files = [...(event.target.files ?? [])]
            event.target.value = ''
            void importPicked(files)
          }}
        />
      </label>
    </Button>
  )

  return (
    <main
      className="px-4 pt-4 pb-6"
      onDragOver={
        desktop
          ? (event) => {
              event.preventDefault()
            }
          : undefined
      }
      onDrop={
        desktop
          ? (event) => {
              event.preventDefault()
              if (busy || importing.current) return
              const files = [...event.dataTransfer.files].filter((file) =>
                /\.(epub|txt|mobi|azw3|fb2|pdf)$/i.test(file.name),
              )
              if (files.length) void importPicked(files)
            }
          : undefined
      }
    >
      {busy && importProgress.total > 0 ? (
        <p role="status" className="mb-3 text-sm text-muted-foreground">
          正在导入 {importProgress.completed} / {importProgress.total} 本…
        </p>
      ) : null}
      {importFailures.length > 0 ? (
        <section aria-label="导入失败的文件" className="mb-4 rounded-lg border p-3 text-sm">
          <p>以下 {importFailures.length} 本未能导入，其余文件已处理：</p>
          <ul className="my-2 max-h-40 overflow-y-auto space-y-1">
            {importFailures.map(({ item, error }, index) => (
              <li key={index} className="break-words">{item.name}：{error}</li>
            ))}
          </ul>
          <Button size="sm" variant="outline" disabled={busy}
            onClick={() => void importPicked(importFailures.map(({ item }) => item))}>
            重试失败文件
          </Button>
          <Button size="sm" variant="ghost" disabled={busy} onClick={() => setImportFailures([])}>
            关闭
          </Button>
        </section>
      ) : null}
      <header className="mb-4 flex items-center justify-between gap-3">
        <h1 className="font-heading text-2xl">书架</h1>
        <div className="flex items-center gap-2">
          {/* View mode toggle */}
          <div className="flex items-center rounded-lg border border-border p-0.5 bg-muted/40">
            <button
              type="button"
              className={`rounded-md p-1.5 transition-colors ${
                viewMode === 'grid'
                  ? 'bg-background text-foreground shadow-xs'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
              title="网格视图"
              onClick={() => setViewModeAndSave('grid')}
            >
              <LayoutGrid className="size-3.5" />
            </button>
            <button
              type="button"
              className={`rounded-md p-1.5 transition-colors ${
                viewMode === 'list'
                  ? 'bg-background text-foreground shadow-xs'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
              title="列表视图"
              onClick={() => setViewModeAndSave('list')}
            >
              <ListIcon className="size-3.5" />
            </button>
          </div>

          <Button
            type="button"
            variant={selecting ? 'secondary' : 'outline'}
            onClick={() => {
              setSelecting((current) => !current)
              setSelected(new Set())
            }}
          >
            {selecting ? '完成' : '选择'}
          </Button>
          {importButton}
        </div>
      </header>

      <div className="mb-5 space-y-2">
        <div className="flex items-center gap-2">
          <Input
            className="min-w-0 flex-1"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索书名或作者…"
            aria-label="搜索书名或作者"
          />
          <Button
            type="button"
            size="icon"
            variant={filtersOpen || filtersActive ? 'secondary' : 'outline'}
            className="relative shrink-0"
            aria-expanded={filtersOpen}
            aria-controls="library-filters"
            title="筛选和排序"
            onClick={() => setFiltersOpen((open) => !open)}
          >
            <SlidersHorizontal />
            <span className="sr-only">{filtersOpen ? '收起筛选' : '筛选和排序'}</span>
            {filtersActive ? (
              <span className="absolute top-1 right-1 size-1.5 rounded-full bg-[#c4a35a]" aria-hidden />
            ) : null}
          </Button>
        </div>
        {filtersOpen ? (
          <div id="library-filters" className="flex flex-wrap gap-2">
            <Select value={filter} onValueChange={(value) => setFilter(value as FilterKey)}>
              <SelectTrigger className="w-28" aria-label="阅读状态">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部状态</SelectItem>
                <SelectItem value="unread">未开始</SelectItem>
                <SelectItem value="reading">阅读中</SelectItem>
                <SelectItem value="done">已读完</SelectItem>
              </SelectContent>
            </Select>
            <Select value={sort} onValueChange={(value) => setSort(value as SortKey)}>
              <SelectTrigger className="w-28" aria-label="排序">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="updated">最近阅读</SelectItem>
                <SelectItem value="title">按标题</SelectItem>
                <SelectItem value="author">按作者</SelectItem>
                <SelectItem value="progress">按进度</SelectItem>
                <SelectItem value="created">导入时间</SelectItem>
              </SelectContent>
            </Select>
            <Select value={tag} onValueChange={setTag}>
              <SelectTrigger className="w-28" aria-label="标签">
                <SelectValue placeholder="标签" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部标签</SelectItem>
                {tags.map((item) => (
                  <SelectItem key={item.id} value={item.name}>
                    {item.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        ) : null}
      </div>

      {/* Empty State */}
      {visible.length === 0 ? (
        books.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
            <div className="size-16 rounded-2xl bg-muted/60 flex items-center justify-center text-muted-foreground mb-4 shadow-inner">
              <BookOpen className="size-8 stroke-[1.5]" />
            </div>
            <h3 className="text-base font-semibold mb-1">书架还是空的</h3>
            <p className="text-muted-foreground text-xs max-w-sm mb-6 leading-relaxed">
              支持导入 EPUB、TXT、MOBI、AZW3、FB2、PDF 电子书
              {desktop ? '，也可以直接将文件拖拽到此窗口。' : '。'}
            </p>
            {importButton}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
            <h3 className="text-base font-semibold mb-1">没有匹配的书</h3>
            <p className="text-muted-foreground text-xs max-w-sm leading-relaxed">
              换个书名或作者，或调整筛选条件。
            </p>
          </div>
        )
      ) : (
        groups.map((group) => (
          <section key={group.id} className="mb-8">
            {group.name ? (
              <div className="mb-3 flex items-center justify-between border-b pb-1">
                <h2 className="text-muted-foreground text-xs font-semibold uppercase tracking-wider">
                  {group.name} ({group.books.length})
                </h2>
              </div>
            ) : null}

            {viewMode === 'grid' ? (
              /* Grid Layout */
              <ul className="grid grid-cols-3 gap-x-3 gap-y-5 sm:grid-cols-4 md:grid-cols-5 xl:grid-cols-7">
                {group.books.map((book) => {
                  const isSelected = selected.has(book.id)
                  return (
                    <li key={book.id} className="group relative">
                      <button
                        type="button"
                        className="w-full text-left"
                        onClick={() => {
                          if (selecting) toggleSelected(book.id)
                          else onOpen(book)
                        }}
                        onContextMenu={(event) => {
                          event.preventDefault()
                          setEditing(book)
                        }}
                      >
                        <div className="relative mb-2 overflow-hidden rounded-md shadow-xs transition-transform duration-200 group-hover:-translate-y-1 group-hover:shadow-md">
                          <div className="aspect-[3/4]">
                            <CoverImage book={book} />
                          </div>
                          {book.progress > 0.001 ? (
                            <span className="absolute inset-x-0 bottom-0 h-1 bg-black/30">
                              <span
                                className="block h-full bg-[#c4a35a]"
                                style={{ width: `${Math.round(book.progress * 100)}%` }}
                              />
                            </span>
                          ) : null}
                          {selecting ? (
                            <span
                              className={`absolute top-1.5 right-1.5 grid size-5 place-items-center rounded-full shadow-sm ${
                                isSelected ? 'bg-primary text-primary-foreground' : 'bg-black/40 text-white'
                              }`}
                            >
                              {isSelected ? <Check className="size-3" /> : null}
                            </span>
                          ) : null}
                        </div>

                        {/* Title: 2 lines clamping */}
                        <strong className="block text-xs font-medium line-clamp-2 leading-snug min-h-[2rem]">
                          {book.title}
                        </strong>

                        {/* Author & Progress */}
                        <div className="mt-1 flex flex-col text-[11px] text-muted-foreground">
                          <span className="truncate">{book.author || '未知作者'}</span>
                          <span className="font-medium text-foreground/70">
                            {book.progress > 0.001 ? `已读 ${Math.round(book.progress * 100)}%` : '未读'}
                          </span>
                        </div>
                      </button>

                      {/* Card more actions button */}
                      {!selecting ? (
                        <button
                          type="button"
                          className="absolute top-1 right-1 rounded-md bg-black/40 p-1 text-white opacity-0 transition-opacity hover:bg-black/60 group-hover:opacity-100"
                          title="管理书籍"
                          onClick={(e) => {
                            e.stopPropagation()
                            setEditing(book)
                          }}
                        >
                          <MoreVertical className="size-3.5" />
                        </button>
                      ) : null}
                    </li>
                  )
                })}
              </ul>
            ) : (
              /* List Layout */
              <div className="divide-y divide-border/60 rounded-lg border border-border/80 bg-card overflow-hidden">
                {group.books.map((book) => {
                  const isSelected = selected.has(book.id)
                  return (
                    <div
                      key={book.id}
                      className="flex items-center justify-between gap-3 p-3 transition-colors hover:bg-muted/40 cursor-pointer"
                      onClick={() => {
                        if (selecting) toggleSelected(book.id)
                        else onOpen(book)
                      }}
                    >
                      <div className="flex items-center gap-3 min-w-0 flex-1">
                        {selecting ? (
                          <span
                            className={`grid size-5 shrink-0 place-items-center rounded-full ${
                              isSelected ? 'bg-primary text-primary-foreground' : 'border border-border'
                            }`}
                          >
                            {isSelected ? <Check className="size-3" /> : null}
                          </span>
                        ) : null}
                        <div className="w-10 h-14 shrink-0 rounded overflow-hidden shadow-xs">
                          <CoverImage book={book} />
                        </div>
                        <div className="min-w-0 flex-1">
                          <strong className="block text-sm truncate font-medium">{book.title}</strong>
                          <p className="text-xs text-muted-foreground truncate mt-0.5">
                            {book.author || '未知作者'}
                          </p>
                        </div>
                      </div>

                      {/* Progress bar and percentage */}
                      <div className="flex items-center gap-4 shrink-0">
                        <div className="w-24 flex flex-col items-end gap-1">
                          <span className="text-xs text-muted-foreground font-mono">
                            {book.progress > 0.001 ? `${Math.round(book.progress * 100)}%` : '未读'}
                          </span>
                          <div className="w-full h-1.5 bg-muted rounded-full overflow-hidden">
                            <div
                              className="h-full bg-[#c4a35a] rounded-full"
                              style={{ width: `${Math.round(book.progress * 100)}%` }}
                            />
                          </div>
                        </div>

                        <Button
                          type="button"
                          variant="ghost"
                          size="icon-xs"
                          onClick={(e) => {
                            e.stopPropagation()
                            setEditing(book)
                          }}
                        >
                          <MoreVertical className="size-4 text-muted-foreground" />
                        </Button>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </section>
        ))
      )}

      {/* Floating Batch Actions Bar */}
      {selecting && selected.size > 0 ? (
        <div className="bg-card/95 backdrop-blur-md sticky bottom-3 flex flex-wrap items-center gap-3 rounded-xl border border-border px-4 py-2.5 shadow-lg">
          <span className="text-sm font-medium">已选 {selected.size} 本书</span>
          <Select
            onValueChange={(shelfId) => {
              void Promise.all(
                [...selected].map((id) => api.addBookToShelf(shelfId, id)),
              )
                .then(reload)
                .then(() => toast.success('已加入目录'))
            }}
          >
            <SelectTrigger className="w-36">
              <SelectValue placeholder="加入目录" />
            </SelectTrigger>
            <SelectContent>
              {shelves.map((shelf) => (
                <SelectItem key={shelf.id} value={shelf.id}>
                  {shelf.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            type="button"
            variant="destructive"
            size="sm"
            onClick={() => setDeleteConfirmTarget('batch')}
          >
            <Trash2 className="size-3.5" />
            删除
          </Button>
        </div>
      ) : null}

      {/* Edit Book Modal */}
      <Dialog open={Boolean(editing)} onOpenChange={(open) => !open && setEditing(null)}>
        <DialogContent>
          <form
            onSubmit={(event) => {
              event.preventDefault()
              if (!editing) return
              const data = new FormData(event.currentTarget)
              void api
                .updateBook(
                  editing.id,
                  String(data.get('title') ?? editing.title),
                  String(data.get('author') ?? ''),
                )
                .then(reload)
                .then(() => {
                  setEditing(null)
                  toast.success('书籍信息已更新')
                })
            }}
          >
            <DialogHeader>
              <DialogTitle>书籍详情</DialogTitle>
              <DialogDescription>修改书籍元数据、管理分类目录或标签。</DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-3">
              <div className="grid gap-1.5">
                <Label htmlFor="title">标题</Label>
                <Input id="title" name="title" defaultValue={editing?.title} />
              </div>
              <div className="grid gap-1.5">
                <Label htmlFor="author">作者</Label>
                <Input id="author" name="author" defaultValue={editing?.author ?? ''} />
              </div>
              <div className="grid gap-1.5">
                <div className="flex items-center justify-between">
                  <Label>目录</Label>
                  <Button
                    type="button"
                    variant="link"
                    size="xs"
                    className="p-0 h-auto"
                    onClick={() => setNewShelfOpen(true)}
                  >
                    <FolderPlus className="size-3 mr-1" />
                    新建目录
                  </Button>
                </div>
                <Select
                  onValueChange={(shelfId) => {
                    if (editing) void api.addBookToShelf(shelfId, editing.id).then(reload)
                  }}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="选择加入目录…" />
                  </SelectTrigger>
                  <SelectContent>
                    {shelves.map((shelf) => (
                      <SelectItem key={shelf.id} value={shelf.id}>
                        {shelf.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-1.5">
                <div className="flex items-center justify-between">
                  <Label>标签</Label>
                  <Button
                    type="button"
                    variant="link"
                    size="xs"
                    className="p-0 h-auto"
                    onClick={() => setNewTagOpen(true)}
                  >
                    <TagIcon className="size-3 mr-1" />
                    新建标签
                  </Button>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {tags.map((item) => {
                    const on = Boolean(editing?.tags.includes(item.name))
                    return (
                      <Button
                        key={item.id}
                        type="button"
                        size="xs"
                        variant={on ? 'default' : 'outline'}
                        onClick={() => {
                          if (!editing) return
                          void api.setBookTag(editing.id, item.id, !on).then(reload)
                        }}
                      >
                        {item.name}
                      </Button>
                    )
                  })}
                  {tags.length === 0 ? (
                    <span className="text-xs text-muted-foreground">暂无标签，可点击上方新建。</span>
                  ) : null}
                </div>
              </div>
            </div>
            <DialogFooter className="flex items-center justify-between sm:justify-between">
              <Button
                type="button"
                variant="destructive"
                onClick={() => {
                  if (editing) setDeleteConfirmTarget(editing)
                }}
              >
                删除书籍
              </Button>
              <div className="flex gap-2">
                <Button type="button" variant="outline" onClick={() => setEditing(null)}>
                  取消
                </Button>
                <Button type="submit">保存</Button>
              </div>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* New Shelf Dialog */}
      <Dialog open={newShelfOpen} onOpenChange={setNewShelfOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>新建目录</DialogTitle>
            <DialogDescription>为书架创建新的分类目录。</DialogDescription>
          </DialogHeader>
          <div className="py-2">
            <Input
              value={newShelfName}
              onChange={(e) => setNewShelfName(e.target.value)}
              placeholder="请输入目录名称"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') void handleCreateShelf()
              }}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setNewShelfOpen(false)}>
              取消
            </Button>
            <Button onClick={() => void handleCreateShelf()}>创建</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* New Tag Dialog */}
      <Dialog open={newTagOpen} onOpenChange={setNewTagOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>新建标签</DialogTitle>
            <DialogDescription>为书籍添加自定义管理标签。</DialogDescription>
          </DialogHeader>
          <div className="py-2">
            <Input
              value={newTagName}
              onChange={(e) => setNewTagName(e.target.value)}
              placeholder="请输入标签名称"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') void handleCreateTag()
              }}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setNewTagOpen(false)}>
              取消
            </Button>
            <Button onClick={() => void handleCreateTag()}>创建</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <Dialog
        open={Boolean(deleteConfirmTarget)}
        onOpenChange={(open) => !open && setDeleteConfirmTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>确认删除？</DialogTitle>
            <DialogDescription>
              {deleteConfirmTarget === 'batch'
                ? `确认要从书架删除选中的 ${selected.size} 本书吗？此操作无法撤销。`
                : `确认要删除《${(deleteConfirmTarget as Book)?.title}》吗？书籍文件与本地进度将被移除。`}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteConfirmTarget(null)}>
              取消
            </Button>
            <Button variant="destructive" onClick={() => void handleDeleteConfirmed()}>
              确认删除
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </main>
  )
}
