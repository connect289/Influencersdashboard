"use client";
import { AtSign, FileText, Lock, Paperclip, Send, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Select, Textarea } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { NOTIFICATIONS_CHANGED } from "@/components/notifications/bell";
import { postMessage, threadUploadUrl } from "@/lib/actions/messaging";
import { fetchThreadView, markThreadReadNow } from "@/lib/messaging/client";
import { formatDateTime } from "@/lib/format";
import type { ThreadView } from "@/lib/messaging/data";
import { encodeMentions, hasUnread, messageParts } from "@/lib/messaging/mentions";
import {
  ATTACHMENT_MAX_BYTES,
  ATTACHMENT_TYPES,
  ATTACHMENTS_BUCKET,
  ATTACHMENTS_MAX,
  isAttachmentType,
  MESSAGE_MAX,
  type Attachment,
  type ThreadRef,
} from "@/lib/messaging/schemas";
import { createClient } from "@/lib/supabase/browser";
import { cn } from "@/lib/utils";

/** How often an open thread looks for new messages while the tab is visible. */
const POLL_MS = 30_000;

/**
 * The conversation about one entity (spec 14): messages with names and times, files, read receipts, @mentions for
 * staff, and a composer for anyone who may write. Re-reads itself after posting and every 30 seconds while visible.
 */
export function ThreadPanel({
  thread,
  initial,
  mentionable = [],
  title,
  description,
}: {
  thread: ThreadRef;
  initial: ThreadView;
  mentionable?: readonly { user_id: string; full_name: string }[];
  title?: string;
  description?: string;
}) {
  const t = useTranslations();
  const [view, setView] = useState(initial);
  const [body, setBody] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [picked, setPicked] = useState<{ name: string; userId: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const listEnd = useRef<HTMLLIElement>(null);
  const ref = useRef(thread);

  const reload = useCallback(async () => {
    const next = await fetchThreadView(ref.current);
    if (next) setView(next);
  }, []);

  // Mark read whenever the panel shows messages from others the reader has not seen.
  useEffect(() => {
    if (view.thread_id && hasUnread(view.messages, view.my_read_at)) {
      const id = view.thread_id;
      void markThreadReadNow(id).then((ok) => {
        if (!ok) return;
        setView((v) => ({ ...v, my_read_at: new Date().toISOString() }));
        window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED));
      });
    }
  }, [view.thread_id, view.messages, view.my_read_at]);

  useEffect(() => {
    const tick = () => {
      if (document.visibilityState === "visible") void reload();
    };
    const id = window.setInterval(tick, POLL_MS);
    document.addEventListener("visibilitychange", tick);
    return () => {
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", tick);
    };
  }, [reload]);

  useEffect(() => {
    listEnd.current?.scrollIntoView({ block: "nearest" });
  }, [view.messages.length]);

  const fileProblem = files.some((f) => !isAttachmentType(f.type) || f.size > ATTACHMENT_MAX_BYTES)
    ? t("messaging.fileRule")
    : files.length > ATTACHMENTS_MAX
      ? t("messaging.errors.tooManyFiles")
      : null;

  async function send() {
    if (busy || fileProblem || (!body.trim() && files.length === 0)) return;
    setBusy(true);
    try {
      const uploaded: Attachment[] = [];
      for (const f of files) {
        if (!isAttachmentType(f.type)) return;
        const signed = await threadUploadUrl({ ...thread, fileName: f.name, mime: f.type, size: f.size });
        if (!signed.ok || !signed.data) {
          toast.error(signed.ok ? t("errors.generic") : signed.error);
          return;
        }
        const up = await createClient()
          .storage.from(ATTACHMENTS_BUCKET)
          .uploadToSignedUrl(signed.data.path, signed.data.token, f, { contentType: f.type });
        if (up.error) {
          toast.error(t("messaging.uploadFailed"));
          return;
        }
        uploaded.push({ path: signed.data.path, name: f.name.slice(0, 200), mime: f.type, size: f.size });
      }
      const r = await postMessage({ ...thread, body: encodeMentions(body.trim(), picked), attachments: uploaded });
      if (!r.ok) {
        toast.error(r.error);
        return;
      }
      setBody("");
      setFiles([]);
      setPicked([]);
      await reload();
    } finally {
      setBusy(false);
    }
  }

  const lastMine = [...view.messages].reverse().find((m) => m.mine);
  const seen =
    lastMine && view.other_read_at && new Date(view.other_read_at).getTime() >= new Date(lastMine.created_at).getTime();

  return (
    <Card>
      <CardHeader title={title ?? t("messaging.title")} description={description} />
      {view.staff_only ? (
        <div className="mb-3">
          <Banner>
            <span className="inline-flex items-center gap-1.5">
              <Lock className="size-3.5" aria-hidden /> {t("messaging.staffOnly")}
            </span>
          </Banner>
        </div>
      ) : null}
      {view.messages.length === 0 ? (
        <p className="text-sm text-muted">{view.can_post ? t("messaging.empty") : t("messaging.emptyReadOnly")}</p>
      ) : (
        <ol className="flex max-h-[28rem] flex-col gap-2 overflow-y-auto pr-1" aria-label={t("messaging.title")}>
          {view.messages.map((m) => (
            <li
              key={m.id}
              className={cn(
                "max-w-[85%] rounded-2xl px-3 py-2 text-sm",
                m.mine ? "self-end bg-primary text-on-primary" : "self-start bg-surface-2",
              )}
            >
              {!m.mine && m.author_name ? <p className="mb-0.5 text-xs font-semibold">{m.author_name}</p> : null}
              {m.body !== "📎" ? (
                <p className="break-words whitespace-pre-line">
                  {messageParts(m.body).map((p, i) =>
                    p.kind === "text" ? (
                      <span key={i}>{p.text}</span>
                    ) : (
                      <strong key={i} className={m.mine ? "underline" : "text-primary"}>
                        @{p.name}
                      </strong>
                    ),
                  )}
                </p>
              ) : null}
              {m.attachments.length > 0 ? (
                <ul className="mt-1 flex flex-col gap-1">
                  {m.attachments.map((a) => (
                    <li key={a.id}>
                      <a
                        href={`/api/threads/file?path=${encodeURIComponent(a.path)}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className={cn(
                          "inline-flex max-w-full items-center gap-1 underline-offset-2 hover:underline",
                          m.mine ? "text-on-primary" : "text-primary",
                        )}
                      >
                        <FileText className="size-4 shrink-0" aria-hidden />
                        <span className="truncate">{a.name}</span>
                      </a>
                    </li>
                  ))}
                </ul>
              ) : null}
              <p className={cn("mt-1 text-[11px]", m.mine ? "text-on-primary/80" : "text-muted")}>
                <time dateTime={m.created_at}>{formatDateTime(m.created_at)}</time>
                {m === lastMine && seen ? ` · ${t("messaging.seen")}` : null}
              </p>
            </li>
          ))}
          <li ref={listEnd} aria-hidden className="h-0" />
        </ol>
      )}
      {view.can_post ? (
        <form
          className="mt-3 flex flex-col gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            void send();
          }}
        >
          <Textarea
            aria-label={t("messaging.write")}
            placeholder={t("messaging.write")}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                void send();
              }
            }}
            maxLength={MESSAGE_MAX}
            rows={2}
          />
          {files.length > 0 ? (
            <ul className="flex flex-wrap gap-1.5" aria-label={t("messaging.files")}>
              {files.map((f, i) => (
                <li
                  key={`${f.name}-${i}`}
                  className="inline-flex items-center gap-1 rounded-lg bg-surface-2 px-2 py-1 text-xs"
                >
                  <FileText className="size-3.5" aria-hidden />
                  <span className="max-w-40 truncate">{f.name}</span>
                  <button
                    type="button"
                    className="rounded p-0.5 text-muted hover:text-ink"
                    aria-label={t("messaging.removeFile", { name: f.name })}
                    onClick={() => setFiles((fs) => fs.filter((_, j) => j !== i))}
                  >
                    <X className="size-3.5" aria-hidden />
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
          {fileProblem ? <p className="text-xs text-danger">{fileProblem}</p> : null}
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-1">
              <input
                ref={fileInput}
                type="file"
                multiple
                accept={ATTACHMENT_TYPES.join(",")}
                className="sr-only"
                tabIndex={-1}
                aria-hidden
                onChange={(e) => {
                  const chosen = [...(e.target.files ?? [])];
                  setFiles((fs) => [...fs, ...chosen].slice(0, ATTACHMENTS_MAX + 1));
                  e.target.value = "";
                }}
              />
              <Button type="button" size="sm" variant="ghost" onClick={() => fileInput.current?.click()}>
                <Paperclip /> {t("messaging.attach")}
              </Button>
              {mentionable.length > 0 && view.side === "eduwit" ? (
                <label className="inline-flex items-center gap-1 text-sm text-muted">
                  <AtSign className="size-4" aria-hidden />
                  <span className="sr-only">{t("messaging.mention")}</span>
                  <Select
                    value=""
                    className="h-8 w-auto py-0 text-sm"
                    onChange={(e) => {
                      const p = mentionable.find((x) => x.user_id === e.target.value);
                      if (!p) return;
                      setPicked((ps) =>
                        ps.some((x) => x.userId === p.user_id) ? ps : [...ps, { name: p.full_name, userId: p.user_id }],
                      );
                      setBody((b) => `${b}${b && !b.endsWith(" ") ? " " : ""}@${p.full_name} `);
                    }}
                  >
                    <option value="">{t("messaging.mention")}</option>
                    {mentionable.map((p) => (
                      <option key={p.user_id} value={p.user_id}>
                        {p.full_name}
                      </option>
                    ))}
                  </Select>
                </label>
              ) : null}
            </div>
            <Button type="submit" size="sm" disabled={busy || !!fileProblem || (!body.trim() && files.length === 0)}>
              <Send /> {busy ? t("messaging.sending") : t("messaging.send")}
            </Button>
          </div>
        </form>
      ) : null}
    </Card>
  );
}
