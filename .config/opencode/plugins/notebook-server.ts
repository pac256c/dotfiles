import type { Plugin, PluginModule } from "@opencode-ai/plugin"
import {
  SESSION_META_KEY,
  appendDiscussion,
  formatStamp,
  readActiveNotebook,
  readNotebook,
  truncate,
  updateNotebook,
  upsertSession,
  type Notebook,
} from "../lib/notebook"

type SessionInfo = {
  slug?: string
  title: string
  updated: number
}

type PendingSession = {
  id: string
  title: string
  updated: number
}

function slugOf(metadata: unknown): string | undefined {
  if (!metadata || typeof metadata !== "object") return undefined
  const value = (metadata as Record<string, unknown>)[SESSION_META_KEY]
  return typeof value === "string" && value.trim() ? value.trim() : undefined
}

function buildSystemBlock(nb: Notebook): string {
  const lines: string[] = [`# Notebook: ${nb.name}`]
  if (nb.description.trim()) lines.push(nb.description.trim())
  lines.push("")
  if (nb.context.trim()) {
    lines.push(nb.context.trim())
    lines.push("")
  }
  if (nb.sessions.length) {
    lines.push("## Sessions in this notebook")
    lines.push("")
    for (const session of nb.sessions.slice(0, 20)) lines.push(`- [${session.id}] ${session.title} — ${session.updated}`)
    lines.push("")
  }
  if (nb.injectDiscussion && nb.discussion.length) {
    lines.push("## Recent discussion")
    lines.push("")
    for (const entry of nb.discussion.slice(-10)) lines.push(`- ${entry}`)
    lines.push("")
  }
  return lines.join("\n").trim()
}

const NotebookServerPlugin: Plugin = async ({ client }) => {
  const sessions = new Map<string, SessionInfo>()
  const texts = new Map<string, { text: string; sessionID: string }>()
  const logged = new Set<string>()
  const pendingSessions = new Map<string, Map<string, PendingSession>>()
  const pendingDiscussion = new Map<string, string[]>()
  let timer: ReturnType<typeof setTimeout> | undefined

  const resolveSession = async (sessionID: string): Promise<SessionInfo | undefined> => {
    const cached = sessions.get(sessionID)
    if (cached) return cached
    try {
      const { data } = await client.session.get({ path: { id: sessionID } })
      if (!data) return undefined
      const info: SessionInfo = {
        slug: slugOf((data as { metadata?: unknown }).metadata),
        title: data.title ?? "",
        updated: data.time?.updated ?? Date.now(),
      }
      sessions.set(sessionID, info)
      return info
    } catch {
      return undefined
    }
  }

  const flush = async () => {
    const wantedBySlug = new Map(pendingSessions)
    const entriesBySlug = new Map(pendingDiscussion)
    pendingSessions.clear()
    pendingDiscussion.clear()
    const slugs = new Set<string>([...wantedBySlug.keys(), ...entriesBySlug.keys()])
    for (const slug of slugs) {
      const wanted = wantedBySlug.get(slug)
      const entries = entriesBySlug.get(slug)
      updateNotebook(slug, (nb) => {
        if (wanted) {
          for (const session of wanted.values()) {
            upsertSession(nb, {
              id: session.id,
              title: session.title,
              updated: formatStamp(session.updated),
            })
          }
        }
        if (entries) for (const entry of entries) appendDiscussion(nb, entry)
      })
    }
  }

  const schedule = () => {
    if (timer) return
    timer = setTimeout(() => {
      timer = undefined
      void flush()
    }, 800)
  }

  const queueSession = (slug: string, session: PendingSession) => {
    const bucket = pendingSessions.get(slug) ?? new Map<string, PendingSession>()
    bucket.set(session.id, session)
    pendingSessions.set(slug, bucket)
    schedule()
  }

  const queueDiscussion = (slug: string, entry: string) => {
    const bucket = pendingDiscussion.get(slug) ?? []
    bucket.push(entry)
    pendingDiscussion.set(slug, bucket)
    schedule()
  }

  const flushMessage = async (messageID: string, who: "you" | "opencode") => {
    const pending = texts.get(messageID)
    if (!pending) return
    texts.delete(messageID)
    if (logged.has(messageID)) return
    const text = truncate(pending.text)
    if (!text) return
    logged.add(messageID)
    const info = await resolveSession(pending.sessionID)
    let slug = info?.slug ?? readActiveNotebook()
    if (!slug) slug = "__none__"
    const title = info?.title || pending.sessionID
    queueDiscussion(slug, `${formatStamp(Date.now())} · ${title} · ${who}: ${text}`)
  }

  return {
    "experimental.chat.system.transform": async (input, output) => {
      const info = input.sessionID ? await resolveSession(input.sessionID) : undefined
      let slug = info?.slug ?? readActiveNotebook()
      if (!slug || slug === "__none__") return
      const nb = readNotebook(slug)
      if (!nb || !nb.inject) return
      const block = buildSystemBlock(nb)
      if (block) output.system.push(block)
    },
    event: async ({ event }) => {
      if (event.type === "session.created" || event.type === "session.updated") {
        const info = event.properties.info
        let slug = slugOf((info as { metadata?: unknown }).metadata)
        if (!slug) slug = "__none__"
        sessions.set(info.id, {
          slug,
          title: info.title ?? "",
          updated: info.time?.updated ?? Date.now(),
        })
        queueSession(slug, { id: info.id, title: info.title ?? "", updated: info.time?.updated ?? Date.now() })
        return
      }
      if (event.type === "message.part.updated") {
        const part = event.properties.part
        if (part.type === "text" && !part.synthetic && !part.ignored) {
          texts.set(part.messageID, { text: part.text, sessionID: part.sessionID })
        }
        return
      }
      if (event.type === "message.updated") {
        const info = event.properties.info
        if (info.role === "assistant" && info.time?.completed) {
          await flushMessage(info.id, "opencode")
        } else if (info.role === "user") {
          await flushMessage(info.id, "you")
        }
        return
      }
    },
  }
}

export default {
  id: "notebook-server",
  server: NotebookServerPlugin,
} satisfies PluginModule
