import { invoke } from '@tauri-apps/api/core'
import { useEffect, useMemo, useState } from 'react'
import { Check, Trash2 } from 'lucide-react'
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

type Props = {
  onOpen: (book: Book) => void
}

const ACCEPT = '.epub,.txt,.mobi,.azw3,.fb2,.pdf,application/epub+zip,text/plain,application/pdf'

type SortKey = 'updated' | 'title' | 'author' | 'progress' | 'created'
type FilterKey = 'all' | 'unread' | 'reading' | 'done'

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
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState<Book | null>(null)
  const [selecting, setSelecting] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const desktop = !isMobile()

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

  const importPicked = async (files: File[]) => {
    if (!files.length) {
      setBusy(false)
      return
    }
    setBusy(true)
    try {
      for (const file of files) {
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
      }
      await reload()
      toast.success(`已导入 ${files.length} 本`)
    } catch (cause) {
      toast.error(String(cause))
    } finally {
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

  const importButton = isAndroid() ? (
    <Button disabled={busy} onClick={() => void onAndroidImport()}>
      {busy ? '导入中…' : '导入'}
    </Button>
  ) : (
    <Button asChild disabled={busy}>
      <label>
        {busy ? '导入中…' : '导入'}
        <input
          hidden
          type="file"
          accept={ACCEPT}
          multiple
          disabled={busy}
          onChange={(event) => {
            const files = event.target.files
            event.target.value = ''
            if (files) void importPicked([...files])
          }}
        />
      </label>
    </Button>
  )

  return (
    <main
      className="px-4 pt-[calc(1rem+env(safe-area-inset-top,0px))] pb-6"
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
              const files = [...event.dataTransfer.files].filter((file) =>
                /\.(epub|txt|mobi|azw3|fb2|pdf)$/i.test(file.name),
              )
              if (files.length) void importPicked(files)
            }
          : undefined
      }
    >
      <header className="mb-4 flex items-center justify-between gap-3">
        <h1 className="font-heading text-2xl">书架</h1>
        <div className="flex gap-2">
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
      <div className="mb-4 flex flex-wrap gap-2">
        <Input
          className="min-w-40 flex-1"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="搜索书名或作者"
        />
        <Select value={filter} onValueChange={(value) => setFilter(value as FilterKey)}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">全部</SelectItem>
            <SelectItem value="unread">未开始</SelectItem>
            <SelectItem value="reading">阅读中</SelectItem>
            <SelectItem value="done">已读完</SelectItem>
          </SelectContent>
        </Select>
        <Select value={sort} onValueChange={(value) => setSort(value as SortKey)}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="updated">最近阅读</SelectItem>
            <SelectItem value="title">标题</SelectItem>
            <SelectItem value="author">作者</SelectItem>
            <SelectItem value="progress">进度</SelectItem>
            <SelectItem value="created">导入时间</SelectItem>
          </SelectContent>
        </Select>
        <Select value={tag} onValueChange={setTag}>
          <SelectTrigger>
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
      {visible.length === 0 ? (
        <p className="text-muted-foreground">
          还没有书。导入 EPUB / TXT / MOBI / AZW3 / FB2 / PDF
          {desktop ? '，或把文件拖到窗口。' : '。'}
        </p>
      ) : (
        groups.map((group) => (
          <section key={group.id} className="mb-6">
            {group.name ? (
              <h2 className="text-muted-foreground mb-3 text-sm font-medium">{group.name}</h2>
            ) : null}
            <ul className="grid grid-cols-3 gap-x-3 gap-y-4 md:grid-cols-5 xl:grid-cols-7">
              {group.books.map((book) => {
                const isSelected = selected.has(book.id)
                return (
                  <li key={book.id}>
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
                      <div className="relative mb-2 overflow-hidden rounded-md">
                        <div className="aspect-[3/4]">
                          <CoverImage book={book} />
                        </div>
                        {book.progress > 0.001 ? (
                          <span className="absolute inset-x-0 bottom-0 h-1 bg-black/20">
                            <span
                              className="block h-full bg-[#c4a35a]"
                              style={{ width: `${Math.round(book.progress * 100)}%` }}
                            />
                          </span>
                        ) : null}
                        {selecting ? (
                          <span
                            className={`absolute top-1.5 right-1.5 grid size-5 place-items-center rounded-full ${
                              isSelected ? 'bg-primary text-primary-foreground' : 'bg-black/35 text-white'
                            }`}
                          >
                            {isSelected ? <Check className="size-3" /> : null}
                          </span>
                        ) : null}
                      </div>
                      <strong className="block truncate text-sm">{book.title}</strong>
                      <span className="text-muted-foreground mt-0.5 block truncate text-xs">
                        {book.author ? `${book.author} · ` : ''}
                        {book.progress > 0.001 ? `${Math.round(book.progress * 100)}%` : '未读'}
                      </span>
                    </button>
                  </li>
                )
              })}
            </ul>
          </section>
        ))
      )}

      {selecting && selected.size > 0 ? (
        <div className="bg-card/95 sticky bottom-3 flex flex-wrap items-center gap-2 rounded-lg border px-3 py-2 shadow-sm">
          <span className="text-sm">已选 {selected.size} 本</span>
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
            onClick={() => {
              if (!window.confirm(`删除选中的 ${selected.size} 本书？`)) return
              void Promise.all([...selected].map((id) => api.deleteBook(id)))
                .then(reload)
                .then(() => {
                  setSelected(new Set())
                  toast.success('已删除')
                })
            }}
          >
            <Trash2 />
            删除
          </Button>
        </div>
      ) : null}

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
                  toast.success('已保存')
                })
            }}
          >
            <DialogHeader>
              <DialogTitle>书籍详情</DialogTitle>
              <DialogDescription>长按或右键打开。删除后会记入同步日志。</DialogDescription>
            </DialogHeader>
            <div className="grid gap-3 py-3">
              <div className="grid gap-1.5">
                <Label htmlFor="title">标题</Label>
                <Input id="title" name="title" defaultValue={editing?.title} />
              </div>
              <div className="grid gap-1.5">
                <Label htmlFor="author">作者</Label>
                <Input id="author" name="author" defaultValue={editing?.author ?? ''} />
              </div>
              <div className="grid gap-1.5">
                <Label>加入目录</Label>
                <Select
                  onValueChange={(shelfId) => {
                    if (editing) void api.addBookToShelf(shelfId, editing.id).then(reload)
                  }}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="选择目录" />
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
                <Label>标签</Label>
                <div className="flex flex-wrap gap-2">
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
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  const name = window.prompt('新目录名称')
                  if (name) void api.createShelf(name).then(reload)
                }}
              >
                新建目录
              </Button>
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  const name = window.prompt('新标签')
                  if (name) void api.createTag(name, 0x3d4a3c).then(reload)
                }}
              >
                新建标签
              </Button>
              <Button
                type="button"
                variant="destructive"
                onClick={() => {
                  if (editing && window.confirm(`删除「${editing.title}」？`)) {
                    void api.deleteBook(editing.id).then(reload).then(() => setEditing(null))
                  }
                }}
              >
                删除
              </Button>
              <Button type="submit">保存</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </main>
  )
}
