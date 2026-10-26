/** @jsxImportSource @opentui/solid */
import { RGBA, type InputRenderable, type KeyEvent } from "@opentui/core"
import type { Session } from "@opencode-ai/sdk/v2"
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { useKeyboard } from "@opentui/solid"
import { For, Show, createEffect, createMemo, createSignal, onMount } from "solid-js"
import {
  ACTIVE_KEY,
  createNotebook,
  listNotebooks,
  removeNotebook,
  renameNotebook,
  type Notebook,
} from "../lib/notebook"

type PluginState = {
  notebooks: () => Notebook[]
  active: () => string | undefined
  sessions: () => Session[]
  setActive: (slug: string | undefined) => Promise<void>
  createSession: () => Promise<void>
}

function NotebookSection(props: { api: TuiPluginApi; state: PluginState }) {
  const theme = () => props.api.theme.current
  const active = createMemo(() => props.state.active())
  const sessions = createMemo(() => props.state.sessions())
  const notebook = createMemo(() => {
    const slug = active()
    if (!slug) return undefined
    return props.state.notebooks().find((item) => item.slug === slug)
  })

  const currentSessionID = () => {
    try {
      const route = (props.api.route as any)?.current
      if (route?.name === "session" && route?.params?.sessionID) return route.params.sessionID
    } catch {}
    return undefined
  }

  return (
    <box flexDirection="column">
      <text fg={theme().text} wrapMode="none" truncate>
        <b>{notebook()?.name ?? "Misc"}</b>
      </text>
      <Show when={sessions().length} fallback={<text fg={theme().textMuted}>No sessions yet</text>}>
        <For each={sessions()}>
          {(session) => (
            <box
              onMouseDown={() => {
                props.api.route.navigate("session", { sessionID: session.id })
              }}
            >
              <text fg={currentSessionID() === session.id ? theme().text : theme().textMuted} wrapMode="none" truncate>
                {session.title || session.id}
              </text>
            </box>
          )}
        </For>
      </Show>
    </box>
  )
}

type NotebookItem = {
  id: string
  kind: "notebook" | "none" | "session" | "new-session" | "blank"
  label: string
  sub: string
  session?: Session
}

function NotebookSelectDialog(props: {
  api: TuiPluginApi
  items: () => NotebookItem[]
  onClose: () => void
  onActivate: (item: NotebookItem) => void
  onCreate: (item: NotebookItem) => void
  onRename: (item: NotebookItem) => void
  onDelete: (item: NotebookItem) => void
  onToggleNotebook?: (slug: string) => void
  onNewNotebook?: () => void
  currentSessionID?: () => string | undefined
}) {
  const theme = () => props.api.theme.current
  const [selected, setSelected] = createSignal(0)
  const [filter, setFilter] = createSignal("")
  let input: InputRenderable | undefined

  onMount(() => {
    props.api.ui.dialog.setSize("large")
    setTimeout(() => {
      if (!input || input.isDestroyed) return
      input.traits = { status: "FILTER" }
      input.focus()
    }, 1)
  })

  const isSelectable = (item: NotebookItem | undefined): item is NotebookItem =>
    !!item && item.kind !== "blank"

  const visibleItems = createMemo(() => {
    const query = filter().trim().toLowerCase()
    const all = props.items()
    if (!query) return all
    const result: NotebookItem[] = []
    let header: NotebookItem | undefined
    let headerMatches = false
    let section: NotebookItem[] = []
    const flush = () => {
      if (!header) return
      const sessions = section.filter((item) => item.kind === "session")
      const news = section.filter((item) => item.kind === "new-session")
      const matches = sessions.filter((item) => item.label.toLowerCase().includes(query))
      if (!headerMatches && matches.length === 0 && news.length === 0) return
      result.push(header)
      if (headerMatches) {
        result.push(...news, ...sessions)
      } else if (matches.length > 0) {
        result.push(...news, ...matches)
      }
      result.push({ id: `__blank__:${header.id}`, kind: "blank", label: "", sub: "" })
    }
    for (const item of all) {
      if (item.kind === "blank") continue
      if (item.kind === "notebook" || item.kind === "none") {
        flush()
        header = item
        headerMatches = item.label.toLowerCase().includes(query)
        section = []
        continue
      }
      section.push(item)
    }
    flush()
    while (result.length > 0 && result[result.length - 1].kind === "blank") result.pop()
    return result
  })

  const selectedIndex = createMemo(() => {
    const list = visibleItems()
    if (!list.length) return 0
    const index = Math.max(0, Math.min(selected(), list.length - 1))
    if (isSelectable(list[index])) return index
    for (let offset = 0; offset < list.length; offset++) {
      const forward = index + offset
      if (forward < list.length && isSelectable(list[forward])) return forward
      const backward = index - offset
      if (backward >= 0 && isSelectable(list[backward])) return backward
    }
    return index
  })

  createEffect(() => {
    const list = visibleItems()
    setSelected((previous) => {
      if (list[previous] && isSelectable(list[previous])) return previous
      const first = list.findIndex(isSelectable)
      return first === -1 ? 0 : first
    })
  })

  const current = () => visibleItems()[selectedIndex()]

  const move = (delta: number) => {
    const list = visibleItems()
    if (!list.length) return
    let index = selectedIndex()
    for (let step = 0; step < list.length; step++) {
      index = (index + delta + list.length) % list.length
      if (isSelectable(list[index])) {
        setSelected(index)
        return
      }
    }
  }

  const toggleHeader = (item: NotebookItem) => {
    const slug = item.kind === "none" ? "__none__" : item.id.startsWith("nb:") ? item.id.slice(3) : undefined
    if (slug && props.onToggleNotebook) props.onToggleNotebook(slug)
  }

  useKeyboard((key: KeyEvent) => {
    if (key.eventType === "release") return
    if (key.name === "escape") {
      key.preventDefault()
      props.onClose()
      return
    }
    if (key.name === "down") {
      key.preventDefault()
      move(1)
      return
    }
    if (key.name === "up" || (key.ctrl && key.name === "p")) {
      key.preventDefault()
      move(-1)
      return
    }
    if (key.ctrl && key.name === "n") {
      key.preventDefault()
      if (props.onNewNotebook) props.onNewNotebook()
      return
    }
    if (key.ctrl && key.name === "r") {
      key.preventDefault()
      const item = current()
      if (item) props.onRename(item)
      return
    }
    if (key.ctrl && key.name === "d") {
      key.preventDefault()
      const item = current()
      if (item) props.onDelete(item)
      return
    }
    if (key.name === "return" || key.name === "kpenter" || key.name === "linefeed") {
      key.preventDefault()
      const item = current()
      if (!item) return
      if (item.kind === "notebook" || item.kind === "none") {
        toggleHeader(item)
        return
      }
      if (item.kind === "blank") return
      if (item.kind === "new-session") {
        props.onCreate(item)
        return
      }
      props.onActivate(item)
      return
    }
  })

  return (
    <box gap={1} paddingBottom={1} flexGrow={1}>
      <box paddingLeft={4} paddingRight={4} flexDirection="row" justifyContent="space-between">
        <text fg={theme().text}>
          <b>Notebooks</b>
        </text>
        <text fg={theme().textMuted} onMouseUp={() => props.onClose()}>
          esc
        </text>
      </box>
      <box paddingLeft={4} paddingRight={4} paddingTop={1}>
        <input
          ref={(element) => (input = element)}
          placeholder="Search"
          onInput={(value) => setFilter(value)}
          focusedBackgroundColor={theme().backgroundPanel}
          cursorColor={theme().primary}
          focusedTextColor={theme().textMuted}
          placeholderColor={theme().textMuted}
        />
      </box>
      <box flexDirection="column" flexGrow={1} flexShrink={1} paddingLeft={1} paddingRight={1}>
        <For each={visibleItems()}>
          {(item, index) => {
            const isSelected = () => selectedIndex() === index()
            const primary = () => theme().primary || theme().accent || theme().text
            if (item.kind === "blank") {
              return <text> </text>
            }
            if (item.kind === "notebook" || item.kind === "none") {
              return (
                <box
                  paddingLeft={3}
                  paddingRight={3}
                  backgroundColor={isSelected() ? primary() : undefined}
                  onMouseDown={() => setSelected(index())}
                  onMouseUp={() => {
                    setSelected(index())
                    toggleHeader(item)
                  }}
                >
                  <text
                    fg={isSelected() ? RGBA.fromInts(0, 0, 0, 255) : primary()}
                    wrapMode="none"
                    truncate
                  >
                    <b>{item.label}</b>
                  </text>
                </box>
              )
            }
            if (item.kind === "new-session") {
              return (
                <box
                  paddingLeft={1}
                  paddingRight={3}
                  backgroundColor={isSelected() ? primary() : undefined}
                  onMouseDown={() => setSelected(index())}
                  onMouseUp={() => {
                    setSelected(index())
                    props.onCreate(item)
                  }}
                >
                  <text
                    fg={isSelected() ? RGBA.fromInts(0, 0, 0, 255) : theme().text}
                    wrapMode="none"
                    truncate
                  >
                    {isSelected() ? <b>{item.label}</b> : item.label}
                  </text>
                </box>
              )
            }
            const isCurrent = () => props.currentSessionID?.() === item.session?.id
            return (
              <box
                paddingLeft={isCurrent() ? 1 : 3}
                paddingRight={3}
                backgroundColor={isSelected() ? primary() : undefined}
                onMouseDown={() => setSelected(index())}
                onMouseUp={() => {
                  setSelected(index())
                  props.onActivate(item)
                }}
              >
                <text
                  fg={
                    isSelected()
                      ? RGBA.fromInts(0, 0, 0, 255)
                      : isCurrent()
                        ? primary()
                        : theme().text
                  }
                  wrapMode="none"
                  truncate
                >
                  {isCurrent() ? "● " : ""}
                  {isSelected() ? <b>{item.label}</b> : item.label}
                </text>
              </box>
            )
          }}
        </For>
      </box>
      <box paddingRight={2} paddingLeft={4} flexDirection="row" justifyContent="space-between" flexShrink={0}>
        <text>
          <span style={{ fg: theme().text }}>rename</span>
          <span style={{ fg: theme().textMuted }}> ctrl+r</span>
          <span style={{ fg: theme().text }}>   delete</span>
          <span style={{ fg: theme().textMuted }}> ctrl+d</span>
          <span style={{ fg: theme().text }}>   new notebook</span>
          <span style={{ fg: theme().textMuted }}> ctrl+n</span>
        </text>
      </box>
    </box>
  )
}

const tui: TuiPlugin = async (api) => {
  const [notebooks, setNotebooks] = createSignal<Notebook[]>([])
  const [active, setActiveSignal] = createSignal<string | undefined>(undefined)
  const [sessions, setSessions] = createSignal<Session[]>([])

  const UNASSIGNED = "__none__"

  const refresh = async () => {
    const list = listNotebooks()
    setNotebooks(list)
    const slug = active() ?? UNASSIGNED
    try {
      const result = await api.client.session.list({ limit: 200 })
      if (result.error) return
      const all = result.data ?? []
      const tagged = all.filter((session) => {
        const value = session.metadata?.notebook
        if (slug === UNASSIGNED) return !value || value === UNASSIGNED
        return typeof value === "string" && value === slug
      })
      tagged.sort((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0))
      setSessions(tagged)
    } catch {
      setSessions([])
    }
  }

  const setActive = async (slug: string | undefined) => {
    const next = !slug || slug === UNASSIGNED ? undefined : slug
    setActiveSignal(next)
    api.kv.set(ACTIVE_KEY, next)
    await refresh()
  }

  const createSession = async (slug?: string) => {
    const target = slug ?? active()
    if (!target) return
    try {
      const result = await api.client.session.create({
        metadata: { notebook: target === "__none__" ? "__none__" : target },
      })
      if (result.error || !result.data) {
        api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not create session" })
        return
      }
      await refresh()
      api.route.navigate("session", { sessionID: result.data.id })
    } catch {
      api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not create session" })
    }
  }

  const renameSession = (session: Session, onDone?: () => void) => {
    const finish = () => {
      if (onDone) queueMicrotask(onDone)
    }
    api.ui.dialog.replace(() => (
      <api.ui.DialogPrompt
        title="Rename session"
        placeholder="Session name"
        value={session.title}
        onConfirm={(value) => {
          const title = value.trim()
          api.ui.dialog.clear()
          if (!title || title === session.title) {
            finish()
            return
          }
          void (async () => {
            try {
              const result = await api.client.session.update({ sessionID: session.id, title })
              if (result.error) {
                api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not rename session" })
                finish()
                return
              }
              await refresh()
              api.ui.toast({ variant: "success", title: "Notebooks", message: `Renamed session to ${title}` })
              finish()
            } catch {
              api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not rename session" })
              finish()
            }
          })()
        }}
        onCancel={() => {
          api.ui.dialog.clear()
          finish()
        }}
      />
    ))
  }

  const deleteSession = async (session: Session, onDone?: () => void) => {
    const finish = () => {
      if (onDone) queueMicrotask(onDone)
    }
    try {
      const result = await api.client.session.delete({ sessionID: session.id })
      if (result.error) {
        api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not delete session" })
        finish()
        return
      }
      await refresh()
      api.ui.toast({ variant: "success", title: "Notebooks", message: "Deleted session" })
      finish()
    } catch {
      api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not delete session" })
      finish()
    }
  }

  const openRenameNotebookDialog = (slug: string, onDone?: () => void) => {
    if (slug === "__none__") return
    const nb = notebooks().find((item) => item.slug === slug)
    if (!nb) return
    const finish = () => {
      if (onDone) queueMicrotask(onDone)
    }
    api.ui.dialog.replace(() => (
      <api.ui.DialogPrompt
        title="Rename notebook"
        placeholder="Notebook name"
        value={nb.name}
        onConfirm={(value) => {
          const name = value.trim()
          api.ui.dialog.clear()
          if (!name || name === nb.name) {
            finish()
            return
          }
          const updated = renameNotebook(slug, name)
          if (!updated) {
            api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not rename notebook" })
            finish()
            return
          }
          void (async () => {
            await refresh()
            api.ui.toast({ variant: "success", title: "Notebooks", message: `Renamed notebook to ${name}` })
            finish()
          })()
        }}
        onCancel={() => {
          api.ui.dialog.clear()
          finish()
        }}
      />
    ))
  }

  const deleteNotebook = (slug: string) => {
    if (slug === "__none__") return
    const nb = notebooks().find((item) => item.slug === slug)
    if (!nb) return
    try {
      removeNotebook(slug)
      if (active() === slug) {
        void setActive("__none__")
      }
      void refresh()
      api.ui.toast({ variant: "success", title: "Notebooks", message: `Deleted ${nb.name}` })
    } catch {
      api.ui.toast({ variant: "error", title: "Notebooks", message: "Could not delete notebook" })
    }
  }

  const openCreateDialog = (onDone?: () => void) => {
    const finish = () => {
      if (onDone) queueMicrotask(onDone)
    }
    api.ui.dialog.replace(() => (
      <api.ui.DialogPrompt
        title="New notebook"
        placeholder="Notebook name"
        onConfirm={(value) => {
          const name = value.trim()
          api.ui.dialog.clear()
          if (!name) {
            finish()
            return
          }
          const nb = createNotebook(name)
          void (async () => {
            await setActive(nb.slug)
            api.ui.toast({ variant: "success", title: "Notebooks", message: `Created ${nb.name}` })
            finish()
          })()
        }}
        onCancel={() => {
          api.ui.dialog.clear()
          finish()
        }}
      />
    ))
  }

  const openNotebookDialog = async () => {
    const allSessions = async (): Promise<Session[]> => {
      try {
        const result = await api.client.session.list({ limit: 200 })
        if (!result.error && result.data) return result.data
      } catch {}
      return []
    }

    let sessionsAll: Session[] = await allSessions()
    const collapsed = new Set<string>()
    const [items, setItems] = createSignal<NotebookItem[]>([])

    const rebuild = () => {
      const allNotebooks = notebooks()
      const activeSlug = active() ?? "__none__"
      const sections: { header: NotebookItem; slug: string; sessions: Session[] }[] = [
        {
          header: { id: "__none__", kind: "none", label: "Misc", sub: "" },
          slug: "__none__",
          sessions: sessionsAll
            .filter((s) => !s.metadata?.notebook || s.metadata?.notebook === "__none__")
            .sort((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0)),
        },
      ]
      for (const nb of allNotebooks) {
        sections.push({
          header: { id: `nb:${nb.slug}`, kind: "notebook", label: nb.name, sub: "" },
          slug: nb.slug,
          sessions: sessionsAll
            .filter((s) => s.metadata?.notebook === nb.slug)
            .sort((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0)),
        })
      }
      sections.sort((a, b) => {
        if (a.slug === activeSlug) return -1
        if (b.slug === activeSlug) return 1
        return 0
      })
      const list: NotebookItem[] = []
      for (const [index, section] of sections.entries()) {
        if (index > 0) {
          list.push({ id: `__blank__:${section.slug}`, kind: "blank", label: "", sub: "" })
        }
        list.push(section.header)
        if (section.slug === activeSlug || !collapsed.has(section.slug)) {
          list.push({
            id: `new:${section.slug}`,
            kind: "new-session",
            label: "+ New Session",
            sub: section.slug,
          })
          for (const s of section.sessions) {
            list.push({
              id: `sess:${section.slug}:${s.id}`,
              kind: "session",
              label: s.title || s.id,
              sub: s.id,
              session: s,
            })
          }
        }
      }
      setItems(list)
    }

    await refresh()
    sessionsAll = await allSessions()
    for (const nb of notebooks()) collapsed.add(nb.slug)
    collapsed.add("__none__")
    collapsed.delete(active() ?? "__none__")
    rebuild()

    const reload = async () => {
      await refresh()
      sessionsAll = await allSessions()
      rebuild()
    }
    const close = () => api.ui.dialog.clear()
    const notebookSlugOf = (item: NotebookItem): string | undefined => {
      if (item.kind === "notebook") return item.id.slice(3)
      if (item.kind === "none") return "__none__"
      if (item.kind === "new-session") return item.sub
      if (item.kind === "session") return item.id.split(":")[1]
      return undefined
    }

    api.ui.dialog.replace(() => (
      <NotebookSelectDialog
        api={api}
        items={items}
        onClose={close}
        onToggleNotebook={(slug) => {
          if (collapsed.has(slug)) collapsed.delete(slug)
          else collapsed.add(slug)
          rebuild()
        }}
        onNewNotebook={() => {
          close()
          queueMicrotask(() => openCreateDialog(openNotebookDialog))
        }}
        currentSessionID={() => {
          try {
            const route = (api.route as any)?.current
            if (route?.name === "session" && route?.params?.sessionID) return route.params.sessionID
          } catch {}
          return undefined
        }}
        onActivate={(item) => {
          if (item.id.startsWith("__blank__")) {
            return
          }
          if (item.kind === "session" && item.session) {
            close()
            const nb = item.session.metadata?.notebook
            const slug = nb && nb !== "__none__" ? String(nb) : undefined
            void setActive(slug)
            api.route.navigate("session", { sessionID: item.session.id })
            return
          }
          const slug = notebookSlugOf(item)
          close()
          void setActive(slug)
        }}
        onCreate={(item) => {
          const slug = notebookSlugOf(item)
          if (!slug) return
          close()
          if (slug === "__none__") void createSession("__none__")
          else void createSession(slug)
        }}
        onRename={(item) => {
          if (item.kind === "session" && item.session) {
            close()
            queueMicrotask(() => renameSession(item.session!, openNotebookDialog))
            return
          }
          if (item.kind === "notebook") {
            close()
            queueMicrotask(() => openRenameNotebookDialog(item.id.slice(3), openNotebookDialog))
            return
          }
        }}
        onDelete={(item) => {
          if (item.kind === "session" && item.session) {
            void deleteSession(item.session, openNotebookDialog)
            return
          }
          if (item.kind === "notebook") {
            deleteNotebook(item.id.slice(3))
            void reload()
            return
          }
        }}
      />
    ))
  }

  const state: PluginState = {
    notebooks,
    active,
    sessions,
    setActive,
    createSession: () => createSession(),
  }

  await refresh()

  api.slots.register({
    order: 150,
    slots: {
      sidebar_content(_ctx, props) {
        return <NotebookSection api={api} state={state} />
      },
    },
  })

  api.keymap.registerLayer({
    commands: [
      {
        name: "notebook.select",
        title: "Notebooks",
        category: "Notebook",
        namespace: "palette",
        slashName: "switch",
        desc: "Manage notebooks",
        run() {
          void openNotebookDialog()
        },
      },
    ],
  })

  let scheduled: ReturnType<typeof setTimeout> | undefined
  const scheduleRefresh = () => {
    if (scheduled) return
    scheduled = setTimeout(() => {
      scheduled = undefined
      void refresh()
    }, 300)
  }

  api.event.on("session.updated", scheduleRefresh)
  api.event.on("session.created", scheduleRefresh)

  const timer = setInterval(() => {
    void refresh()
  }, 10000)
  api.lifecycle.onDispose(() => {
    clearInterval(timer)
    if (scheduled) clearTimeout(scheduled)
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id: "notebook-tui",
  tui,
}

export default plugin
