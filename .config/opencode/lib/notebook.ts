import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

export const MANAGED_START = "<!-- opencode:managed:start -->"
export const MANAGED_END = "<!-- opencode:managed:end -->"
export const ACTIVE_KEY = "notebook.active"
export const SESSION_META_KEY = "notebook"
export const DISCUSSION_LIMIT = 200
export const DISCUSSION_ENTRY_LIMIT = 400

export type NotebookSession = {
  id: string
  title: string
  updated: string
}

export type Notebook = {
  slug: string
  name: string
  description: string
  created: string
  updated: string
  inject: boolean
  injectDiscussion: boolean
  context: string
  sessions: NotebookSession[]
  discussion: string[]
}

export function stateDir(): string {
  const xdg = process.env.XDG_STATE_HOME
  const base = xdg && xdg.trim() ? xdg : join(homedir(), ".local", "state")
  return join(base, "opencode")
}

export function notebookDir(): string {
  return join(stateDir(), "notebooks")
}

export function kvFile(): string {
  return join(stateDir(), "kv.json")
}

export function slugify(input: string): string {
  return (
    input
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 64) || "notebook"
  )
}

function unquote(value: string): string {
  if (value.length >= 2) {
    const first = value[0]
    const last = value[value.length - 1]
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) return value.slice(1, -1)
  }
  return value
}

function parseFrontmatter(text: string): { data: Record<string, string>; body: string } {
  const match = /^---\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?/.exec(text)
  if (!match) return { data: {}, body: text }
  const data: Record<string, string> = {}
  for (const line of match[1].split(/\r?\n/)) {
    const idx = line.indexOf(":")
    if (idx <= 0) continue
    const key = line.slice(0, idx).trim()
    if (!key) continue
    data[key] = unquote(line.slice(idx + 1).trim())
  }
  return { data, body: text.slice(match[0].length) }
}

function parseSessions(lines: string[]): NotebookSession[] {
  const sessions: NotebookSession[] = []
  for (const line of lines) {
    const match = /^-?\s*\[([^\]]+)\] (.*?) — (.*)$/.exec(line.trim())
    if (!match) continue
    sessions.push({ id: match[1], title: match[2], updated: match[3] })
  }
  return sessions
}

function parseSections(body: string): { context: string; sessions: NotebookSession[]; discussion: string[] } {
  const start = body.indexOf(MANAGED_START)
  const end = body.indexOf(MANAGED_END)
  const context = (start === -1 ? body : body.slice(0, start)).trim()
  const sessions: NotebookSession[] = []
  const discussion: string[] = []
  if (start === -1 || end === -1 || end < start) return { context, sessions, discussion }
  const managed = body.slice(start + MANAGED_START.length, end)
  let section = ""
  let sessionLines: string[] = []
  let discussionLines: string[] = []
  for (const line of managed.split(/\r?\n/)) {
    const heading = /^##\s+(.+?)\s*$/.exec(line)
    if (heading) {
      if (section === "Sessions") sessions.push(...parseSessions(sessionLines))
      if (section === "Discussion") discussion.push(...discussionLines)
      section = heading[1]
      sessionLines = []
      discussionLines = []
      continue
    }
    const bullet = /^-\s+(.*)$/.exec(line.trim())
    if (!bullet) continue
    if (section === "Sessions") sessionLines.push(bullet[1])
    if (section === "Discussion") discussionLines.push(bullet[1])
  }
  if (section === "Sessions") sessions.push(...parseSessions(sessionLines))
  if (section === "Discussion") discussion.push(...discussionLines)
  return { context, sessions, discussion }
}

export function parseNotebook(slug: string, text: string): Notebook {
  const { data, body } = parseFrontmatter(text)
  const { context, sessions, discussion } = parseSections(body)
  return {
    slug,
    name: data.name || slug,
    description: data.description || "",
    created: data.created || "",
    updated: data.updated || "",
    inject: data.inject !== "false",
    injectDiscussion: data.inject_discussion === "true",
    context,
    sessions,
    discussion,
  }
}

export function renderNotebook(nb: Notebook): string {
  const head = [
    "---",
    `name: ${nb.name}`,
    `description: ${nb.description}`,
    `created: ${nb.created}`,
    `updated: ${nb.updated}`,
    `inject: ${nb.inject}`,
    `inject_discussion: ${nb.injectDiscussion}`,
    "---",
    "",
  ].join("\n")
  const context = nb.context.trim() ? `${nb.context.trim()}\n\n` : ""
  const managed = [
    MANAGED_START,
    "## Sessions",
    "",
    ...nb.sessions.map((s) => `- [${s.id}] ${s.title} — ${s.updated}`),
    "",
    "## Discussion",
    "",
    ...nb.discussion.map((entry) => `- ${entry}`),
    MANAGED_END,
    "",
  ].join("\n")
  return `${head}${context}${managed}`
}

export function notebookPath(slug: string): string {
  return join(notebookDir(), `${slug}.md`)
}

export function listNotebooks(): Notebook[] {
  const dir = notebookDir()
  if (!existsSync(dir)) return []
  const files = readdirSync(dir).filter((file) => file.endsWith(".md"))
  const notebooks: Notebook[] = []
  for (const file of files) {
    const slug = file.slice(0, -3)
    const nb = readNotebook(slug)
    if (nb) notebooks.push(nb)
  }
  return notebooks.sort((a, b) => a.name.localeCompare(b.name))
}

export function readNotebook(slug: string): Notebook | undefined {
  const file = notebookPath(slug)
  if (!existsSync(file)) return undefined
  try {
    return parseNotebook(slug, readFileSync(file, "utf8"))
  } catch {
    return undefined
  }
}

export function writeNotebook(nb: Notebook): void {
  mkdirSync(notebookDir(), { recursive: true })
  const file = notebookPath(nb.slug)
  const tmp = `${file}.tmp-${process.pid}`
  writeFileSync(tmp, renderNotebook(nb), "utf8")
  renameSync(tmp, file)
}

export function createNotebook(name: string, description = ""): Notebook {
  const slug = uniqueSlug(slugify(name))
  const now = new Date().toISOString()
  const nb: Notebook = {
    slug,
    name: name.trim() || slug,
    description: description.trim(),
    created: now,
    updated: now,
    inject: true,
    injectDiscussion: false,
    context: "## Context\n",
    sessions: [],
    discussion: [],
  }
  writeNotebook(nb)
  return nb
}

export function uniqueSlug(base: string): string {
  if (!existsSync(notebookPath(base))) return base
  for (let i = 2; i < 100; i++) {
    const candidate = `${base}-${i}`
    if (!existsSync(notebookPath(candidate))) return candidate
  }
  return `${base}-${Date.now()}`
}

export function updateNotebook(slug: string, mutate: (nb: Notebook) => void): Notebook | undefined {
  const nb = readNotebook(slug)
  if (!nb) return undefined
  const before = renderNotebook(nb)
  mutate(nb)
  if (renderNotebook(nb) === before) return nb
  nb.updated = new Date().toISOString()
  writeNotebook(nb)
  return nb
}

export function renameNotebook(slug: string, name: string): Notebook | undefined {
  const next = name.trim()
  if (!next) return undefined
  return updateNotebook(slug, (nb) => {
    nb.name = next
  })
}

export function upsertSession(nb: Notebook, session: NotebookSession): void {
  const existing = nb.sessions.find((item) => item.id === session.id)
  if (existing) {
    existing.title = session.title || existing.title
    existing.updated = session.updated
  } else {
    nb.sessions.unshift(session)
  }
}

export function appendDiscussion(nb: Notebook, entry: string): void {
  nb.discussion.push(entry)
  if (nb.discussion.length > DISCUSSION_LIMIT) nb.discussion = nb.discussion.slice(-DISCUSSION_LIMIT)
}

export function readActiveNotebook(): string | undefined {
  try {
    const raw = readFileSync(kvFile(), "utf8")
    const parsed = JSON.parse(raw) as Record<string, unknown>
    const value = parsed[ACTIVE_KEY]
    if (typeof value === "string" && value.trim()) return value.trim()
  } catch {
    return undefined
  }
  return undefined
}

export function writeActiveNotebook(slug: string | undefined): void {
  const file = kvFile()
  let parsed: Record<string, unknown> = {}
  try {
    parsed = JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>
  } catch {
    parsed = {}
  }
  if (slug) parsed[ACTIVE_KEY] = slug
  else delete parsed[ACTIVE_KEY]
  mkdirSync(stateDir(), { recursive: true })
  const tmp = `${file}.tmp-${process.pid}`
  writeFileSync(tmp, `${JSON.stringify(parsed, null, 2)}\n`, "utf8")
  renameSync(tmp, file)
}

export function removeNotebook(slug: string): void {
  const file = notebookPath(slug)
  if (existsSync(file)) rmSync(file)
}

export function formatStamp(value: number | string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function truncate(value: string, limit = DISCUSSION_ENTRY_LIMIT): string {
  const flat = value.replace(/\s+/g, " ").trim()
  if (flat.length <= limit) return flat
  return `${flat.slice(0, limit - 1)}…`
}
