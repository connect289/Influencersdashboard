"use client";
import { useRouter } from "next/navigation";
import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import { ActionCard, type ActionCardData } from "@/components/chat/action-card.tsx";
import { Markdown } from "@/components/chat/markdown.tsx";
import { SecretForm } from "@/components/settings/setup-forms.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Textarea } from "@/components/ui/field.tsx";
import type { ChatEvent } from "@/lib/ai/chat/engine.ts";
import type { ChatAction, ChatMessageRow } from "@/lib/ai/chat/db.ts";
import { ago } from "@/lib/format.ts";

// The conversation (D-094): the turns so far, the streaming answer, the tools it used, the action cards you confirm
// or decline and the Vault cards for secrets. A turn is one POST to /api/chat read as a stream of JSON lines; nothing
// here talks to the database directly.

type ToolChip = { name: string; status: "running" | "ok" | "error"; rows?: number; error?: string };

type Item =
  | { kind: "user"; key: string; text: string; at?: string }
  | {
      kind: "assistant";
      key: string;
      text: string;
      tools: ToolChip[];
      error?: string;
      at?: string;
      streaming?: boolean;
    }
  | { kind: "action"; key: string; action: ActionCardData }
  | { kind: "outcome"; key: string; text: string; tone: "ok" | "p1" | "off" }
  | { kind: "secret"; key: string; name: string; item?: string }
  | { kind: "note"; key: string; text: string; tone: "p1" | "p2" | "neutral" };

const STARTERS = [
  "What needs me right now?",
  "Walk me through setting up Witty, step by step.",
  "What does Spark still need before it is fully watched?",
  "Why is the newest P1 open, and what can we do about it?",
];

function fromRows(messages: ChatMessageRow[], actions: ChatAction[]): Item[] {
  const byId = new Map(actions.map((a) => [a.id, a]));
  const items: Item[] = [];
  for (const m of messages) {
    const c = m.content;
    if (m.role === "user") {
      items.push({ kind: "user", key: `m${m.id}`, text: String(c.text ?? ""), at: m.created_at });
    } else if (m.role === "assistant") {
      const tools = Array.isArray(c.tools)
        ? (c.tools as Array<Record<string, unknown>>).map((t) => ({
            name: String(t.name),
            status: (t.ok ? "ok" : "error") as ToolChip["status"],
            rows: typeof t.rows === "number" ? t.rows : undefined,
            error: typeof t.error === "string" ? t.error : undefined,
          }))
        : [];
      items.push({
        kind: "assistant",
        key: `m${m.id}`,
        text: String(c.text ?? ""),
        tools,
        error: typeof c.error === "string" ? c.error : undefined,
        at: m.created_at,
      });
      for (const id of Array.isArray(c.actions) ? (c.actions as unknown[]) : []) {
        const a = typeof id === "number" ? byId.get(id) : undefined;
        if (a) {
          items.push({
            kind: "action",
            key: `a${a.id}`,
            action: {
              id: a.id,
              tool: a.tool,
              args: a.args,
              summary: a.summary,
              risk: a.risk,
              status: a.status,
              error: a.error ?? null,
            },
          });
        }
      }
    } else {
      const status = String(c.status ?? "");
      items.push({
        kind: "outcome",
        key: `m${m.id}`,
        text: `${String(c.summary ?? c.tool ?? "action")}: ${status}${c.error ? ` (${String(c.error)})` : ""}`,
        tone: status === "done" ? "ok" : status === "failed" ? "p1" : "off",
      });
    }
  }
  return items;
}

export function ChatPanel({
  threadId,
  messages,
  actions,
  busy,
  role,
}: {
  threadId: number | null;
  messages: ChatMessageRow[];
  actions: ChatAction[];
  busy: boolean;
  role: "owner" | "engineer";
}) {
  const router = useRouter();
  const [thread, setThread] = useState<number | null>(threadId);
  const [items, setItems] = useState<Item[]>(() => fromRows(messages, actions));
  const [text, setText] = useState("");
  const [sending, setSending] = useState(busy);
  const bottom = useRef<HTMLDivElement>(null);
  const seq = useRef(0);
  const key = (p: string) => `${p}${++seq.current}`;

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [items]);

  function update(k: string, f: (it: Item) => Item) {
    setItems((list) => list.map((it) => (it.key === k ? f(it) : it)));
  }

  async function send(message: string) {
    const t = message.trim();
    if (!t || sending) return;
    setSending(true);
    setText("");
    const userKey = key("u");
    const asstKey = key("s");
    setItems((list) => [
      ...list,
      { kind: "user", key: userKey, text: t },
      { kind: "assistant", key: asstKey, text: "", tools: [], streaming: true },
    ]);
    let newThread = false;
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ thread_id: thread, text: t }),
      });
      if (!res.ok || !res.body) {
        const why =
          res.status === 401
            ? "Your session has ended; sign in again."
            : res.status === 503
              ? "The app is not configured yet (Setup item one_app_env)."
              : "The chat could not answer. Try again.";
        update(asstKey, (it) => (it.kind === "assistant" ? { ...it, streaming: false, error: why } : it));
        return;
      }
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      const handle = (e: ChatEvent) => {
        switch (e.t) {
          case "start":
            if (thread === null) {
              newThread = true;
              setThread(e.thread_id);
              window.history.replaceState(null, "", `/chat?t=${e.thread_id}`);
            }
            break;
          case "text":
            update(asstKey, (it) => (it.kind === "assistant" ? { ...it, text: it.text + e.d } : it));
            break;
          case "tool":
            update(asstKey, (it) => {
              if (it.kind !== "assistant") return it;
              const tools = [...it.tools];
              const i = tools.findLastIndex((c) => c.name === e.name && c.status === "running");
              const chip: ToolChip = { name: e.name, status: e.status, rows: e.rows, error: e.error };
              if (e.status !== "running" && i >= 0) tools[i] = chip;
              else tools.push(chip);
              return { ...it, tools };
            });
            break;
          case "action":
            setItems((list) => [
              ...list,
              { kind: "action", key: `a${e.action.id}`, action: { ...e.action, status: "proposed", error: null } },
            ]);
            break;
          case "secret":
            setItems((list) => [...list, { kind: "secret", key: key("k"), name: e.name, item: e.item }]);
            break;
          case "done":
            update(asstKey, (it) =>
              it.kind === "assistant" ? { ...it, text: e.text || it.text, streaming: false } : it,
            );
            break;
          case "refused":
            update(asstKey, (it) => (it.kind === "assistant" ? { ...it, text: e.message, streaming: false } : it));
            break;
          case "error":
            update(asstKey, (it) => (it.kind === "assistant" ? { ...it, streaming: false, error: e.message } : it));
            break;
        }
      };
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let nl;
        while ((nl = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, nl).trim();
          buffer = buffer.slice(nl + 1);
          if (!line) continue;
          try {
            handle(JSON.parse(line) as ChatEvent);
          } catch {
            // a malformed line is skipped
          }
        }
      }
    } catch {
      update(asstKey, (it) =>
        it.kind === "assistant" ? { ...it, streaming: false, error: "The connection dropped. Try again." } : it,
      );
    } finally {
      setSending(false);
      update(asstKey, (it) => (it.kind === "assistant" && it.streaming ? { ...it, streaming: false } : it));
      if (newThread) router.refresh();
    }
  }

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    void send(text);
  }
  function onKey(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send(text);
    }
  }

  return (
    <div className="grid min-h-[60vh] grid-rows-[1fr_auto] gap-3">
      <div className="grid content-start gap-3" aria-live="polite">
        {items.length === 0 ? (
          <div className="grid gap-3 rounded-md border border-dashed border-border p-4 text-sm text-fg-muted">
            <p>
              Ask anything about the five apps, or tell me what to do. I read the live state with fixed tools, I act
              only through the same buttons you have, and anything beyond a small step shows you a card to confirm
              first.
              {role === "engineer" ? " Owner-only changes (fix switches, access, money) stay with the owner." : ""}
            </p>
            <div className="flex flex-wrap gap-2">
              {STARTERS.map((s) => (
                <Button key={s} variant="secondary" size="sm" onClick={() => void send(s)} disabled={sending}>
                  {s}
                </Button>
              ))}
            </div>
          </div>
        ) : null}
        {items.map((it) => (
          <ChatItem key={it.key} item={it} />
        ))}
        <div ref={bottom} />
      </div>
      <form onSubmit={onSubmit} className="grid gap-2 border-t border-border pt-3">
        <Textarea
          name="text"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKey}
          rows={2}
          maxLength={4000}
          className="min-h-12"
          placeholder={sending ? "Answering…" : "Ask or tell me what to do. Enter sends, Shift+Enter is a new line."}
          disabled={sending}
          aria-label="Your message"
        />
        <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-fg-muted">
          <span>
            Phones and emails are masked before the AI sees them; never paste a key here, I will offer a Vault card.
          </span>
          <Button type="submit" size="sm" disabled={sending || !text.trim()}>
            {sending ? "Answering…" : "Send"}
          </Button>
        </div>
      </form>
    </div>
  );
}

function ChatItem({ item }: { item: Item }) {
  switch (item.kind) {
    case "user":
      return (
        <div className="ml-auto max-w-[85%] rounded-md bg-primary px-3 py-2 text-sm text-primary-fg whitespace-pre-line [overflow-wrap:anywhere]">
          {item.text}
        </div>
      );
    case "assistant":
      return (
        <div className="grid max-w-[95%] gap-2 rounded-md border border-border bg-surface px-3 py-2">
          {item.tools.length ? (
            <ul className="flex flex-wrap gap-1 text-xs" aria-label="Tools used">
              {item.tools.map((t, i) => (
                <li
                  key={i}
                  className={
                    "rounded border px-1.5 py-0.5 font-mono " +
                    (t.status === "error"
                      ? "border-p1 text-p1"
                      : t.status === "running"
                        ? "border-border text-fg-muted"
                        : "border-border text-fg")
                  }
                  title={t.error ?? undefined}
                >
                  {t.name}
                  {t.status === "running"
                    ? "…"
                    : t.status === "ok" && t.rows !== undefined
                      ? ` · ${t.rows}`
                      : t.status === "error"
                        ? " · error"
                        : ""}
                </li>
              ))}
            </ul>
          ) : null}
          {item.text ? (
            <Markdown text={item.text} />
          ) : item.streaming ? (
            <p className="text-sm text-fg-muted">Thinking…</p>
          ) : null}
          {item.error ? (
            <p role="alert" className="text-sm text-p1">
              {item.error}
            </p>
          ) : null}
          {item.at ? <p className="text-xs text-fg-muted">{ago(item.at)}</p> : null}
        </div>
      );
    case "action":
      return <ActionCard action={item.action} />;
    case "outcome":
      return (
        <p className={`text-xs ${item.tone === "ok" ? "text-ok" : item.tone === "p1" ? "text-p1" : "text-fg-muted"}`}>
          {item.text}
        </p>
      );
    case "secret":
      return (
        <div className="grid gap-2 rounded-md border border-accent bg-surface p-3 text-sm">
          <p className="font-medium">
            Paste the secret for <code>{item.name}</code>
            {item.item ? ` (Setup item ${item.item})` : ""}. It goes straight to Vault; the AI never sees it.
          </p>
          <SecretForm name={item.name} />
        </div>
      );
    case "note":
      return (
        <p className={`text-sm ${item.tone === "p1" ? "text-p1" : item.tone === "p2" ? "text-p2" : "text-fg-muted"}`}>
          {item.text}
        </p>
      );
  }
}
