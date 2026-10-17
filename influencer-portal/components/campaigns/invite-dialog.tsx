"use client";
import { Search, Send, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { inviteToCampaign } from "@/lib/actions/campaigns";
import { searchCreators } from "@/lib/actions/creators";

interface Pick {
  id: string;
  name: string;
  handle: string;
}

/** Pick creators by name or handle and invite them with a short message. */
export function InviteDialog({ campaignId }: { campaignId: string }) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<Pick[]>([]);
  const [picked, setPicked] = useState<Pick[]>([]);
  const [message, setMessage] = useState("");
  const { pending, run } = useAction();
  const active = q.trim().length >= 2;
  useEffect(() => {
    if (!active) return;
    let live = true;
    const id = setTimeout(() => {
      void searchCreators(q).then((r) => {
        if (live) setHits(r);
      });
    }, 250);
    return () => {
      live = false;
      clearTimeout(id);
    };
  }, [q, active]);
  const chosen = new Set(picked.map((p) => p.id));
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <Send /> {t("campaigns.invites.invite")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("campaigns.invites.invite")}
        description={t("campaigns.invites.hint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                inviteToCampaign(
                  campaignId,
                  picked.map((p) => p.id),
                  message,
                ),
              () => {
                setOpen(false);
                setPicked([]);
                setMessage("");
              },
            );
          }}
        >
          {picked.length ? (
            <ul className="flex flex-wrap gap-1.5">
              {picked.map((p) => (
                <li key={p.id}>
                  <Badge family="progress" className="gap-1 py-1">
                    {p.name}
                    <button
                      type="button"
                      aria-label={t("common.remove")}
                      onClick={() => setPicked(picked.filter((x) => x.id !== p.id))}
                    >
                      <X className="size-3" />
                    </button>
                  </Badge>
                </li>
              ))}
            </ul>
          ) : null}
          <div className="relative">
            <Search
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
              aria-hidden
            />
            <Input
              aria-label={t("campaigns.invites.find")}
              placeholder={t("campaigns.invites.find")}
              value={q}
              onChange={(e) => setQ(e.target.value)}
              className="pl-9"
            />
          </div>
          {active && hits.length ? (
            <ul className="max-h-48 overflow-y-auto rounded-xl ring-1 ring-line ring-inset">
              {hits.map((h) => (
                <li key={h.id}>
                  <button
                    type="button"
                    disabled={chosen.has(h.id)}
                    onClick={() => {
                      setPicked([...picked, h]);
                      setQ("");
                    }}
                    className="w-full px-3 py-2 text-left text-sm hover:bg-surface-2 disabled:opacity-50"
                  >
                    {h.name} <span className="text-xs text-muted">@{h.handle}</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
          <p className="text-xs text-muted">{t("campaigns.invites.onlyApproved")}</p>
          <Field id="inv-msg" label={t("campaigns.invites.message")}>
            <Textarea id="inv-msg" value={message} onChange={(e) => setMessage(e.target.value)} maxLength={2000} />
          </Field>
          <Button type="submit" disabled={pending || picked.length === 0}>
            {t("campaigns.invites.send", { count: picked.length })}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
