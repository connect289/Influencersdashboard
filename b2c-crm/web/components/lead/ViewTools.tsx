"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Link2, Pin, PinOff } from "lucide-react";
import { toast } from "sonner";
import { viewPin } from "@/app/s/actions";
import { fieldDef, GROUPABLE } from "@/lib/viewFields";

/** Pin the view as the page's default, copy a link to it (others of the same role open it if it is shared with them). */
export function ViewTools({ role, base, viewId, pinned, shareable }: { role: "sales" | "workspace"; base: string; viewId: number; pinned: boolean; shareable: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const pin = () => start(async () => {
    const r = await viewPin(role, pinned ? null : viewId);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  const copy = async () => {
    const url = `${window.location.origin}${base}?view=${viewId}`;
    try {
      await navigator.clipboard.writeText(url);
      toast.success(shareable ? "Link copied." : "Link copied. Share the view with your role first, or only you can open it.");
    } catch {
      prompt("Copy this link", url);
    }
  };
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={pin} disabled={busy} aria-pressed={pinned} title={pinned ? "Stop opening on this view" : "Open the Leads page on this view"}>
        {pinned ? <PinOff className="icon s" aria-hidden /> : <Pin className="icon s" aria-hidden />}{pinned ? "Unpin" : "Pin as default"}
      </button>
      <button type="button" className="btn quiet sm" onClick={copy}><Link2 className="icon s" aria-hidden />Copy link</button>
    </>
  );
}

/** Group the rows of the current view by a field (counts, and commission totals for Admin and Marketing). */
export function GroupBySelect({ value, href, allowed }: { value: string; href: Record<string, string>; allowed: string[] }) {
  const router = useRouter();
  return (
    <select className="input" style={{ width: "auto", minHeight: "var(--control-sm)" }} value={value} aria-label="Group by"
      onChange={(e) => router.push(href[e.target.value] ?? href[""]!)}>
      <option value="">No grouping</option>
      {GROUPABLE.filter((g) => allowed.includes(g)).map((g) => <option key={g} value={g}>Group by {fieldDef(g)?.label.toLowerCase() ?? g}</option>)}
    </select>
  );
}
