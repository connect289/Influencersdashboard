"use client";
// Going live: the creator schedules (when that stage is on) and submits the live link; a reviewer checks it is live,
// carries the disclosure and matches the approved version.
import { ExternalLink } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { scheduleDeliverable, submitLivePost, verifyLivePost } from "@/lib/actions/content";
import type { PublishedPost } from "@/lib/content/data";
import { formatDate, formatDateTime, istToday } from "@/lib/format";

export function ScheduleForm({ deliverableId, current }: { deliverableId: string; current: string | null }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [at, setAt] = useState("");
  return (
    <form
      className="flex flex-col gap-3 md:flex-row md:items-end"
      onSubmit={(e) => {
        e.preventDefault();
        // The picker gives local IST wall time; store the instant.
        run(
          () => scheduleDeliverable({ deliverableId, at: new Date(`${at}:00+05:30`).toISOString() }),
          () => router.refresh(),
        );
      }}
    >
      <Field
        id="sch-at"
        label={t("content.live.scheduleAt")}
        hint={
          current ? t("content.live.scheduledFor", { at: formatDateTime(current) }) : t("content.live.scheduleHint")
        }
      >
        <Input id="sch-at" type="datetime-local" required value={at} onChange={(e) => setAt(e.target.value)} />
      </Field>
      <Button type="submit" disabled={pending || !at}>
        {t("content.live.schedule")}
      </Button>
    </form>
  );
}

export function GoLiveForm({ deliverableId, correcting }: { deliverableId: string; correcting: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const today = istToday();
  const [url, setUrl] = useState("");
  const [postedOn, setPostedOn] = useState(today);
  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => submitLivePost({ deliverableId, url, postedOn }),
          () => {
            setUrl("");
            router.refresh();
          },
        );
      }}
    >
      <Field
        id="live-url"
        label={correcting ? t("content.live.correctUrl") : t("content.live.url")}
        hint={t("content.live.urlHint")}
      >
        <Input
          id="live-url"
          inputMode="url"
          placeholder="https://"
          required
          maxLength={1000}
          value={url}
          onChange={(e) => setUrl(e.target.value)}
        />
      </Field>
      <Field id="live-date" label={t("content.live.postedOn")}>
        <Input
          id="live-date"
          type="date"
          required
          max={today}
          value={postedOn}
          onChange={(e) => setPostedOn(e.target.value)}
        />
      </Field>
      <Button type="submit" className="self-start" disabled={pending || !url.trim()}>
        {t("content.live.submit")}
      </Button>
    </form>
  );
}

function VerifyForm({ deliverableId, postId }: { deliverableId: string; postId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState({ live: true, disclosure: true, matches: true });
  const [note, setNote] = useState("");
  const ok = v.live && v.disclosure && v.matches;
  return (
    <form
      className="mt-3 flex flex-col gap-2 rounded-xl p-3 ring-1 ring-line"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => verifyLivePost({ deliverableId, postId, ...v, note }),
          () => router.refresh(),
        );
      }}
    >
      <p className="text-sm font-medium">{t("content.live.verifyTitle")}</p>
      {(["live", "disclosure", "matches"] as const).map((k) => (
        <label key={k} className="flex items-start gap-2 text-sm">
          <input
            type="checkbox"
            className="mt-0.5 size-4"
            checked={v[k]}
            onChange={(e) => setV({ ...v, [k]: e.target.checked })}
          />
          <span>{t(`content.live.verifyItems.${k}`)}</span>
        </label>
      ))}
      <Field id={`vf-note-${postId}`} label={ok ? t("content.live.verifyNote") : t("content.live.rejectNote")}>
        <Input id={`vf-note-${postId}`} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <Button
        type="submit"
        size="sm"
        variant={ok ? "primary" : "danger"}
        className="self-start"
        disabled={pending || (!ok && note.trim().length < 3)}
      >
        {ok ? t("content.live.verify") : t("content.live.reject")}
      </Button>
    </form>
  );
}

export function PostsList({
  deliverableId,
  posts,
  canVerify,
}: {
  deliverableId: string;
  posts: PublishedPost[];
  canVerify: boolean;
}) {
  const t = useTranslations();
  if (!posts.length) return <p className="text-sm text-muted">{t("content.live.none")}</p>;
  return (
    <ul className="flex flex-col gap-3">
      {posts.map((p) => (
        <li key={p.id} className="rounded-xl bg-surface-2 p-3 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={p.verification_status} label={t(`content.live.statuses.${p.verification_status}`)} />
            <a
              href={p.live_url}
              target="_blank"
              rel="noopener noreferrer nofollow"
              className="inline-flex min-w-0 items-center gap-1 break-all text-primary hover:underline"
            >
              {p.live_url} <ExternalLink className="size-3.5 shrink-0" aria-hidden />
            </a>
          </div>
          <p className="mt-1 text-xs text-muted">{t("content.live.postedLine", { date: formatDate(p.posted_on) })}</p>
          {p.oembed?.title ? (
            <div className="mt-2 flex items-center gap-3">
              {p.oembed.thumbnail_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={p.oembed.thumbnail_url}
                  alt=""
                  className="h-14 w-24 rounded object-cover"
                  loading="lazy"
                  referrerPolicy="no-referrer"
                />
              ) : null}
              <span>
                <span className="block font-medium">{p.oembed.title}</span>
                {p.oembed.author_name ? <span className="text-xs text-muted">{p.oembed.author_name}</span> : null}
              </span>
            </div>
          ) : null}
          {p.review_note ? <p className="mt-1">{t("content.live.reviewNote", { note: p.review_note })}</p> : null}
          {canVerify && p.verification_status === "pending" ? (
            <VerifyForm deliverableId={deliverableId} postId={p.id} />
          ) : null}
        </li>
      ))}
    </ul>
  );
}

export function LiveCard({ children }: { children: React.ReactNode }) {
  const t = useTranslations();
  return (
    <Card>
      <CardHeader title={t("content.live.title")} />
      {children}
    </Card>
  );
}
