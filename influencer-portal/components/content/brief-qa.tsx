"use client";
// Questions and answers on a brief: the creator (or their agency) asks, Eduwit answers; everyone sees the thread.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { addBriefQuestion } from "@/lib/actions/content";
import type { BriefQuestion } from "@/lib/content/data";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";

function Bubble({ q }: { q: BriefQuestion }) {
  const t = useTranslations();
  return (
    <div
      className={cn(
        "rounded-xl px-3 py-2 text-sm",
        q.author_side === "eduwit" ? "bg-primary-soft" : "bg-surface-2",
      )}
    >
      <p className="mb-0.5 text-xs text-muted">
        {t(`content.qa.sides.${q.author_side}`)} · {formatDateTime(q.created_at)}
      </p>
      <p className="whitespace-pre-line">{q.body}</p>
    </div>
  );
}

function Composer({
  briefId,
  parentId,
  placeholder,
  onDone,
}: {
  briefId: string;
  parentId: string | null;
  placeholder: string;
  onDone?: () => void;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [body, setBody] = useState("");
  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => addBriefQuestion({ briefId, body, parentId }),
          () => {
            setBody("");
            onDone?.();
            router.refresh();
          },
        );
      }}
    >
      <Textarea
        aria-label={placeholder}
        placeholder={placeholder}
        rows={2}
        maxLength={4000}
        value={body}
        onChange={(e) => setBody(e.target.value)}
      />
      <Button type="submit" size="sm" className="self-end" disabled={pending || !body.trim()}>
        {parentId ? t("content.qa.reply") : t("content.qa.ask")}
      </Button>
    </form>
  );
}

export function BriefQa({
  briefId,
  threads,
  canAsk,
  canAnswer,
}: {
  briefId: string;
  threads: { root: BriefQuestion; replies: BriefQuestion[] }[];
  /** The creator or agency (on a published brief). */
  canAsk: boolean;
  /** Staff who can write briefs. */
  canAnswer: boolean;
}) {
  const t = useTranslations();
  const [replying, setReplying] = useState<string | null>(null);
  return (
    <Card>
      <CardHeader title={t("content.qa.title")} description={t("content.qa.hint")} />
      {threads.length === 0 ? (
        <p className="mb-3 text-sm text-muted">{t("content.qa.empty")}</p>
      ) : null}
      <ul className="mb-4 flex flex-col gap-4">
        {threads.map(({ root, replies }) => (
          <li key={root.id} className="flex flex-col gap-2">
            <Bubble q={root} />
            {replies.map((r) => (
              <div key={r.id} className="ml-6">
                <Bubble q={r} />
              </div>
            ))}
            {canAnswer || canAsk ? (
              replying === root.id ? (
                <div className="ml-6">
                  <Composer
                    briefId={briefId}
                    parentId={root.id}
                    placeholder={t("content.qa.replyPlaceholder")}
                    onDone={() => setReplying(null)}
                  />
                </div>
              ) : (
                <Button
                  type="button"
                  variant="link"
                  size="sm"
                  className="ml-6 self-start px-0"
                  onClick={() => setReplying(root.id)}
                >
                  {t("content.qa.reply")}
                </Button>
              )
            ) : null}
          </li>
        ))}
      </ul>
      {canAsk || canAnswer ? (
        <Composer
          briefId={briefId}
          parentId={null}
          placeholder={canAsk ? t("content.qa.askPlaceholder") : t("content.qa.notePlaceholder")}
        />
      ) : null}
    </Card>
  );
}
