"use client";
// Clause-anchored negotiation under each section: the comment thread (replies, resolve) and, for the creator or their
// agency on a negotiable clause, "suggest wording" (suggestion mode: they propose the full new wording; Eduwit
// accepts, counters or rejects it, and an accepted wording becomes the clause text in the next version).
import { MessageSquare } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { addContractComment, requestContractChange, resolveContractComment } from "@/lib/actions/contracts";
import type { Block, RichDoc } from "@/lib/contracts/doc";
import { formatDateTime } from "@/lib/format";
import { RichEditor } from "./rich-editor";

export interface ThreadComment {
  id: string;
  parent_id: string | null;
  author_side: "creator" | "agency" | "eduwit";
  body: string;
  created_at: string;
  resolved: boolean;
  mine: boolean;
}

function CommentForm({
  contractId,
  clauseKey,
  parentId,
  label,
  onDone,
}: {
  contractId: string;
  clauseKey: string;
  parentId: string | null;
  label: string;
  onDone?: () => void;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [body, setBody] = useState("");
  const id = `cm-${clauseKey}-${parentId ?? "root"}`;
  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => addContractComment({ contractId, clauseKey, body, parentId }),
          () => {
            setBody("");
            onDone?.();
          },
        );
      }}
    >
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <Textarea
        id={id}
        rows={2}
        value={body}
        placeholder={label}
        onChange={(e) => setBody(e.target.value)}
        maxLength={4000}
        required
      />
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={pending || body.trim() === ""}>
          {t("contracts.comments.post")}
        </Button>
      </div>
    </form>
  );
}

function SuggestDialog({ contractId, clauseKey, blocks }: { contractId: string; clauseKey: string; blocks: Block[] }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const initial: RichDoc = { type: "doc", content: blocks.filter((b) => b.type !== "table") };
  const [doc, setDoc] = useState<RichDoc>(initial);
  const [note, setNote] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary" size="sm">
          {t("contracts.requests.suggest")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("contracts.requests.suggestTitle")}
        description={t("contracts.requests.suggestHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => requestContractChange({ contractId, kind: "clause", clauseKey, body: doc, note }),
              () => setOpen(false),
            );
          }}
        >
          <RichEditor
            id={`sg-${clauseKey}`}
            label={t("contracts.requests.wording")}
            value={initial}
            onChange={setDoc}
          />
          <Field id={`sg-note-${clauseKey}`} label={t("contracts.requests.why")}>
            <Textarea
              id={`sg-note-${clauseKey}`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={1000}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending}>
              {t("contracts.requests.send")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function ClauseThread({
  contractId,
  clauseKey,
  comments,
  canComment,
  canSuggest,
  hasPendingSuggestion,
  blocks,
}: {
  contractId: string;
  clauseKey: string;
  comments: ThreadComment[];
  canComment: boolean;
  canSuggest: boolean;
  hasPendingSuggestion: boolean;
  blocks: Block[];
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const open = comments.filter((c) => !c.resolved).length;
  const [expanded, setExpanded] = useState(open > 0);
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const roots = comments.filter((c) => c.parent_id === null);
  const replies = (id: string) => comments.filter((c) => c.parent_id === id);
  if (!canComment && comments.length === 0) return null;
  const sideLabel = (s: ThreadComment["author_side"]) => t(`contracts.sides.${s}`);

  const item = (c: ThreadComment) => (
    <div className={c.resolved ? "opacity-60" : undefined}>
      <p className="flex flex-wrap items-center gap-2 text-xs text-muted">
        <span className="font-medium text-ink">{c.mine ? t("contracts.comments.you") : sideLabel(c.author_side)}</span>
        <span>{formatDateTime(c.created_at)}</span>
        {c.resolved ? <Badge>{t("contracts.comments.resolvedBadge")}</Badge> : null}
      </p>
      <p className="mt-0.5 text-sm whitespace-pre-wrap">{c.body}</p>
      {canComment && !c.resolved ? (
        <div className="mt-1 flex gap-3 text-xs">
          {c.parent_id === null ? (
            <button type="button" className="text-primary hover:underline" onClick={() => setReplyTo(c.id)}>
              {t("contracts.comments.reply")}
            </button>
          ) : null}
          <button
            type="button"
            className="text-muted hover:underline"
            disabled={pending}
            onClick={() => run(() => resolveContractComment(c.id, contractId))}
          >
            {t("contracts.comments.resolve")}
          </button>
        </div>
      ) : null}
    </div>
  );

  return (
    <div className="mt-2 rounded-lg bg-surface-2 p-2 print:hidden">
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          aria-expanded={expanded}
          onClick={() => setExpanded((x) => !x)}
          className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-muted hover:text-ink"
        >
          <MessageSquare className="size-4" aria-hidden />
          {comments.length
            ? t("contracts.comments.count", { count: comments.length, open })
            : t("contracts.comments.add")}
        </button>
        {canSuggest && !hasPendingSuggestion ? (
          <SuggestDialog contractId={contractId} clauseKey={clauseKey} blocks={blocks} />
        ) : null}
        {hasPendingSuggestion ? <Badge family="attention">{t("contracts.requests.pendingBadge")}</Badge> : null}
      </div>
      {expanded ? (
        <div className="mt-2 flex flex-col gap-3 px-2 pb-1">
          {roots.map((c) => (
            <div key={c.id} className="flex flex-col gap-2">
              {item(c)}
              {replies(c.id).length || replyTo === c.id ? (
                <div className="ml-4 flex flex-col gap-2 border-l border-line pl-3">
                  {replies(c.id).map((r) => (
                    <div key={r.id}>{item(r)}</div>
                  ))}
                  {replyTo === c.id ? (
                    <CommentForm
                      contractId={contractId}
                      clauseKey={clauseKey}
                      parentId={c.id}
                      label={t("contracts.comments.replyPlaceholder")}
                      onDone={() => setReplyTo(null)}
                    />
                  ) : null}
                </div>
              ) : null}
            </div>
          ))}
          {canComment ? (
            <CommentForm
              contractId={contractId}
              clauseKey={clauseKey}
              parentId={null}
              label={t("contracts.comments.placeholder")}
            />
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
