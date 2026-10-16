"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { when } from "@/lib/format";
import { campaignReplies, type CampaignReply } from "../admin-actions";

const CLASS_CHIP: Record<string, string> = { positive: "ok", interested: "ok", negative: "breach", opt_out: "breach", not_interested: "breach", question: "soft" };

/** The replies that followed a campaign, within 7 days of each send (b2c.campaign_replies). */
export function CampaignRepliesTable({ campaign }: { campaign: number }) {
  const [rows, setRows] = useState<CampaignReply[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void campaignReplies(campaign).then((r) => { if (!live) return; if (r.ok) setRows(r.data ?? []); else setError(r.error); });
    return () => { live = false; };
  }, [campaign]);
  if (error) return <p className="error" role="alert">{error}</p>;
  if (!rows) return <p className="note">Loading the replies…</p>;
  if (rows.length === 0) return <p className="note">No replies within 7 days of a send yet.</p>;
  return (
    <div className="stack" style={{ gap: 6 }}>
      <h3 className="eyebrow">Replies ({rows.length}{rows.length >= 200 ? "+" : ""})</h3>
      <div className="table-wrap"><table>
        <thead><tr><th>Student</th><th>Reply</th><th>Class</th><th>When</th></tr></thead>
        <tbody>{rows.map((r) => (
          <tr key={r.reply_id}>
            <td><Link href={`/w/leads/${r.lead_id}`}>{r.name ?? `Lead #${r.lead_id}`}</Link><div className="small muted">{r.channel === "whatsapp" ? "WhatsApp" : r.channel}{r.variant ? ` · ${r.variant.toUpperCase()}` : ""}</div></td>
            <td className="small" style={{ maxWidth: 320 }}>{r.text ?? "—"}</td>
            <td>{r.class ? <span className={`chip ${CLASS_CHIP[r.class] ?? "line"}`}>{r.class.replace(/_/g, " ")}</span> : "—"}<div className="small muted">{r.status}</div></td>
            <td className="small nowrap">{when(r.at)}</td>
          </tr>
        ))}</tbody>
      </table></div>
    </div>
  );
}
