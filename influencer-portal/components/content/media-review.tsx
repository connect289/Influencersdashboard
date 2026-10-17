"use client";
// One submission with its files and comments. Comments can point at a moment in the video (timestamp) or an area
// of an image (drag to mark it); clicking a comment jumps to the moment or highlights the area.
import { Check, Clock, ExternalLink, MapPin, RotateCcw } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { addReviewComment, setCommentResolved } from "@/lib/actions/content";
import type { ImageRegion, ReviewComment, Submission } from "@/lib/content/data";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import { fileIcon } from "./upload-field";

export function formatTimestamp(ms: number): string {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, "0");
  return h ? `${String(h)}:${String(m).padStart(2, "0")}:${sec}` : `${String(m)}:${sec}`;
}

function ImageAnnotator({
  src,
  alt,
  index,
  regions,
  active,
  draft,
  onDraft,
  enabled,
}: {
  src: string;
  alt: string;
  index: number;
  regions: { id: string; n: number; r: ImageRegion }[];
  active: string | null;
  draft: ImageRegion | null;
  onDraft: (r: ImageRegion | null) => void;
  enabled: boolean;
}) {
  const box = useRef<HTMLDivElement>(null);
  const start = useRef<{ x: number; y: number } | null>(null);
  const pos = (e: React.PointerEvent) => {
    const b = box.current?.getBoundingClientRect();
    if (!b) return { x: 0, y: 0 };
    return {
      x: Math.min(1, Math.max(0, (e.clientX - b.left) / b.width)),
      y: Math.min(1, Math.max(0, (e.clientY - b.top) / b.height)),
    };
  };
  const round = (n: number) => Math.round(n * 1000) / 1000;
  return (
    <div
      ref={box}
      className={cn("relative inline-block max-w-full touch-none select-none", enabled && "cursor-crosshair")}
      onPointerDown={(e) => {
        if (!enabled) return;
        (e.target as Element).setPointerCapture(e.pointerId);
        start.current = pos(e);
        onDraft({ file: index, ...start.current, w: 0, h: 0 });
      }}
      onPointerMove={(e) => {
        if (!start.current) return;
        const p = pos(e);
        const s = start.current;
        onDraft({
          file: index,
          x: round(Math.min(s.x, p.x)),
          y: round(Math.min(s.y, p.y)),
          w: round(Math.abs(p.x - s.x)),
          h: round(Math.abs(p.y - s.y)),
        });
      }}
      onPointerUp={() => {
        start.current = null;
      }}
    >
      {/* Signed storage URLs: next/image would proxy and cache private files. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt={alt} className="max-h-[70vh] max-w-full rounded-lg" draggable={false} />
      {[...regions, ...(draft && draft.file === index ? [{ id: "draft", n: 0, r: draft }] : [])].map(({ id, n, r }) => (
        <span
          key={id}
          aria-hidden
          className={cn(
            "pointer-events-none absolute rounded border-2",
            id === "draft" ? "border-accent" : id === active ? "border-primary bg-primary/15" : "border-primary/70",
            r.w === 0 && r.h === 0 && "size-3 -translate-x-1/2 -translate-y-1/2 rounded-full",
          )}
          style={{
            left: `${String(r.x * 100)}%`,
            top: `${String(r.y * 100)}%`,
            ...(r.w || r.h ? { width: `${String(r.w * 100)}%`, height: `${String(r.h * 100)}%` } : {}),
          }}
        >
          {n ? (
            <span className="absolute -top-5 -left-0.5 rounded bg-primary px-1 text-[10px] text-on-primary">{n}</span>
          ) : null}
        </span>
      ))}
    </div>
  );
}

export function MediaReview({
  deliverableId,
  submission,
  links,
  comments,
  canComment,
}: {
  deliverableId: string;
  submission: Submission;
  links: Record<string, string>;
  comments: ReviewComment[];
  canComment: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const video = useRef<HTMLVideoElement>(null);
  const [body, setBody] = useState("");
  const [atTime, setAtTime] = useState(false);
  const [region, setRegion] = useState<ImageRegion | null>(null);
  const [active, setActive] = useState<string | null>(null);
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const [reply, setReply] = useState("");
  const files = submission.files;
  const hasVideo = files.some((f) => f.type.startsWith("video/"));
  const roots = comments.filter((c) => c.parent_id === null);
  const numbered = roots
    .filter((c) => c.image_region)
    .map((c, i) => ({ id: c.id, n: i + 1, r: c.image_region as ImageRegion }));

  const jump = (c: ReviewComment) => {
    setActive(c.id);
    if (c.video_timestamp_ms !== null && video.current) {
      video.current.currentTime = c.video_timestamp_ms / 1000;
      void video.current.play().catch(() => undefined);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      {submission.body ? (
        <p className="rounded-xl bg-surface-2 p-3 text-sm whitespace-pre-line">{submission.body}</p>
      ) : null}
      {submission.link_url ? (
        <a
          href={submission.link_url}
          target="_blank"
          rel="noopener noreferrer nofollow"
          className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
        >
          {t("content.review.openLink")} <ExternalLink className="size-3.5" aria-hidden />
        </a>
      ) : null}
      {submission.creator_note ? (
        <p className="text-sm text-muted">{t("content.review.creatorNote", { note: submission.creator_note })}</p>
      ) : null}
      {files.map((f, i) => {
        const url = links[f.path];
        if (!url)
          return (
            <p key={f.path} className="flex items-center gap-2 text-sm text-muted">
              {fileIcon(f.type)} {f.name}
            </p>
          );
        if (f.type.startsWith("video/") && files.findIndex((x) => x.type.startsWith("video/")) === i)
          return (
            <video
              key={f.path}
              ref={video}
              src={url}
              controls
              preload="metadata"
              playsInline
              className="max-h-[70vh] w-full rounded-lg bg-black"
            >
              <track kind="captions" />
            </video>
          );
        if (f.type.startsWith("image/"))
          return (
            <ImageAnnotator
              key={f.path}
              src={url}
              alt={f.name}
              index={i}
              regions={numbered.filter((x) => x.r.file === i)}
              active={active}
              draft={region}
              onDraft={setRegion}
              enabled={canComment}
            />
          );
        return (
          <a
            key={f.path}
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 text-sm text-primary hover:underline"
          >
            {fileIcon(f.type)} {f.name}
          </a>
        );
      })}

      <section className="flex flex-col gap-2" aria-label={t("content.comments.title")}>
        <h3 className="text-sm font-semibold">{t("content.comments.title")}</h3>
        {roots.length === 0 ? <p className="text-sm text-muted">{t("content.comments.empty")}</p> : null}
        <ul className="flex flex-col gap-2">
          {roots.map((c) => {
            const n = numbered.find((x) => x.id === c.id)?.n;
            return (
              <li
                key={c.id}
                className={cn(
                  "rounded-xl p-3 text-sm",
                  c.resolved ? "bg-surface-2 opacity-70" : "bg-surface-2",
                  active === c.id && "ring-2 ring-primary",
                )}
              >
                <div className="mb-1 flex flex-wrap items-center gap-2 text-xs text-muted">
                  <span>{t(`content.qa.sides.${c.author_side}`)}</span>
                  <span>{formatDateTime(c.created_at)}</span>
                  {c.video_timestamp_ms !== null ? (
                    <button
                      type="button"
                      className="inline-flex items-center gap-1 text-primary hover:underline"
                      onClick={() => jump(c)}
                    >
                      <Clock className="size-3" aria-hidden /> {formatTimestamp(c.video_timestamp_ms)}
                    </button>
                  ) : null}
                  {n ? (
                    <button
                      type="button"
                      className="inline-flex items-center gap-1 text-primary hover:underline"
                      onClick={() => jump(c)}
                    >
                      <MapPin className="size-3" aria-hidden /> {t("content.comments.area", { n })}
                    </button>
                  ) : null}
                  {c.resolved ? <Badge family="success">{t("content.comments.resolved")}</Badge> : null}
                </div>
                <p className="whitespace-pre-line">{c.body}</p>
                {comments
                  .filter((r) => r.parent_id === c.id)
                  .map((r) => (
                    <div key={r.id} className="mt-2 ml-4 border-l-2 border-line pl-3">
                      <p className="text-xs text-muted">
                        {t(`content.qa.sides.${r.author_side}`)} · {formatDateTime(r.created_at)}
                      </p>
                      <p className="whitespace-pre-line">{r.body}</p>
                    </div>
                  ))}
                {canComment ? (
                  <div className="mt-2 flex flex-wrap gap-2">
                    <Button
                      type="button"
                      variant="link"
                      size="sm"
                      className="px-0"
                      onClick={() => setReplyTo(replyTo === c.id ? null : c.id)}
                    >
                      {t("content.qa.reply")}
                    </Button>
                    <Button
                      type="button"
                      variant="link"
                      size="sm"
                      className="px-0"
                      disabled={pending}
                      onClick={() =>
                        run(
                          () => setCommentResolved(c.id, !c.resolved, deliverableId),
                          () => router.refresh(),
                        )
                      }
                    >
                      {c.resolved ? <RotateCcw /> : <Check />}{" "}
                      {c.resolved ? t("content.comments.reopen") : t("content.comments.resolve")}
                    </Button>
                  </div>
                ) : null}
                {replyTo === c.id ? (
                  <form
                    className="mt-2 flex flex-col gap-2"
                    onSubmit={(e) => {
                      e.preventDefault();
                      run(
                        () =>
                          addReviewComment({
                            deliverableId,
                            submissionId: submission.id,
                            body: reply,
                            parentId: c.id,
                          }),
                        () => {
                          setReply("");
                          setReplyTo(null);
                          router.refresh();
                        },
                      );
                    }}
                  >
                    <Textarea
                      aria-label={t("content.qa.replyPlaceholder")}
                      rows={2}
                      maxLength={4000}
                      value={reply}
                      onChange={(e) => setReply(e.target.value)}
                    />
                    <Button type="submit" size="sm" className="self-end" disabled={pending || !reply.trim()}>
                      {t("content.qa.reply")}
                    </Button>
                  </form>
                ) : null}
              </li>
            );
          })}
        </ul>
        {canComment ? (
          <form
            className="flex flex-col gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              const ms = atTime && video.current ? Math.round(video.current.currentTime * 1000) : null;
              run(
                () =>
                  addReviewComment({
                    deliverableId,
                    submissionId: submission.id,
                    body,
                    timestampMs: ms,
                    region:
                      region && (region.w > 0.005 || region.h > 0.005 || (region.w === 0 && region.h === 0))
                        ? region
                        : null,
                  }),
                () => {
                  setBody("");
                  setRegion(null);
                  router.refresh();
                },
              );
            }}
          >
            <Textarea
              aria-label={t("content.comments.placeholder")}
              placeholder={t("content.comments.placeholder")}
              rows={2}
              maxLength={4000}
              value={body}
              onChange={(e) => setBody(e.target.value)}
            />
            <div className="flex flex-wrap items-center gap-3 text-sm">
              {hasVideo ? (
                <label className="inline-flex items-center gap-2">
                  <input
                    type="checkbox"
                    className="size-4"
                    checked={atTime}
                    onChange={(e) => setAtTime(e.target.checked)}
                  />
                  {t("content.comments.atTime")}
                </label>
              ) : null}
              {region ? (
                <span className="inline-flex items-center gap-1 text-accent-ink">
                  <MapPin className="size-3.5" aria-hidden /> {t("content.comments.areaMarked")}
                  <Button type="button" variant="link" size="sm" className="px-1" onClick={() => setRegion(null)}>
                    {t("common.clear")}
                  </Button>
                </span>
              ) : files.some((f) => f.type.startsWith("image/")) ? (
                <span className="text-xs text-muted">{t("content.comments.dragHint")}</span>
              ) : null}
              <Button type="submit" size="sm" className="ml-auto" disabled={pending || !body.trim()}>
                {t("content.comments.add")}
              </Button>
            </div>
          </form>
        ) : null}
      </section>
    </div>
  );
}
