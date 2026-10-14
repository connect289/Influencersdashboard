"use client";
import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { CircleHelp } from "lucide-react";
import { Sheet } from "@/components/ui/Sheet";
import { guideRead, guidesList, type Article } from "@/app/guide-actions";
import { Markdown, screenMatches } from "@/lib/markdown";

/** The contextual "?" (spec B16): the guide articles for this screen, in a side panel next to it. */
export function HelpButton() {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const [articles, setArticles] = useState<Article[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function show() {
    setOpen(true);
    guidesList().then((r) => {
      if (!r.ok) return setError(r.error);
      const all = r.data ?? [];
      const here = all.filter((a) => a.screens.some((s) => screenMatches(s, path)));
      setArticles(here);
      for (const a of here) if (!a.read) void guideRead(a.id);
    });
  }

  const full = path.startsWith("/s") ? "/s/me?tab=guide" : "/w/guide";
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={show} aria-label="Help for this screen"><CircleHelp className="icon s" aria-hidden /></button>
      {open && (
        <Sheet title="Help" onClose={() => setOpen(false)}>
          {error && <p className="error">{error}</p>}
          {!articles && !error && <p className="note">Loading…</p>}
          {articles && articles.length === 0 && <p className="note">No article for this screen yet.</p>}
          {articles?.map((a) => (
            <section key={a.id} className="md">
              <h3>{a.title}</h3>
              <Markdown text={a.body} />
            </section>
          ))}
          <Link className="btn ghost block" href={full} onClick={() => setOpen(false)}>The whole guide</Link>
        </Sheet>
      )}
    </>
  );
}
