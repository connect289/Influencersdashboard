"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { programmeSend } from "@/app/s/workspace-actions";
import { shareText } from "@/lib/compose";
import type { Programme } from "@/lib/programmes";

const HTTPS = /^https:\/\//;

/**
 * Sends one to four programmes to the lead (spec B8.3, B8.9): on WhatsApp the message plus each brochure as a document
 * (inside the 24-hour window), by email with the brochure links, or records that they were explained on a call or in a meeting.
 */
export function ShareSheet({ leadId, rows, firstName, counsellor, hasEmail, onDone, onClose }: {
  leadId: number; rows: Programme[]; firstName: string | null; counsellor: string | null; hasEmail: boolean; onDone: () => void; onClose: () => void;
}) {
  const router = useRouter();
  const [channel, setChannel] = useState<"whatsapp" | "email" | "call" | "meeting">("whatsapp");
  const [text, setText] = useState(() => shareText(rows, firstName, counsellor));
  const [subject, setSubject] = useState(rows.length > 1 ? "The programmes we discussed" : `${rows[0]?.name}, ${rows[0]?.university}`);
  const [note, setNote] = useState("");
  const brochures = rows.filter((r) => r.brochure_url && HTTPS.test(r.brochure_url)).map((r) => ({ url: r.brochure_url!, name: `${r.name}, ${r.university_short ?? r.university}`.slice(0, 120) }));
  const [withBrochures, setWithBrochures] = useState(brochures.length > 0);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const sends = channel === "whatsapp" || channel === "email";

  function share() {
    setError(null);
    start(async () => {
      const r = await programmeSend({
        lead: leadId, programmes: rows.map((x) => x.id), channel, text: sends ? text : undefined, subject: channel === "email" ? subject : undefined,
        note: sends ? undefined : note, brochures: channel === "whatsapp" && withBrochures ? brochures : undefined,
      });
      if (!r.ok) return setError(r.error);
      toast.success(r.notice ?? "Shared.");
      onDone();
      router.refresh();
    });
  }

  return (
    <Sheet title={rows.length > 1 ? `Share ${rows.length} programmes` : "Share a programme"} onClose={onClose}>
      <div className="pills" role="radiogroup" aria-label="How">
        {([["whatsapp", "WhatsApp"], ["email", "Email"], ["call", "Explained on a call"], ["meeting", "In a meeting"]] as const).map(([k, l]) => (
          <button key={k} type="button" className="pill" role="radio" aria-checked={channel === k} aria-pressed={channel === k} onClick={() => setChannel(k)}
            disabled={k === "email" && !hasEmail} title={k === "email" && !hasEmail ? "This lead has no email" : undefined}>{l}</button>
        ))}
      </div>
      {channel === "whatsapp" && <p className="note">Free text and files go only within 24 hours of the student&apos;s last message. Outside it, open the chat with a template first.</p>}
      {channel === "email" && (
        <label className="field"><span>Subject</span><input className="input" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={300} /></label>
      )}
      {sends ? (
        <label className="field"><span>Message</span><textarea className="input" rows={10} value={text} onChange={(e) => setText(e.target.value)} maxLength={4000} /></label>
      ) : (
        <label className="field"><span>Note (optional)</span><input className="input" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} placeholder="For example: fees and EMI explained" /></label>
      )}
      {channel === "whatsapp" && brochures.length > 0 && (
        <label className="checkbox"><input type="checkbox" checked={withBrochures} onChange={(e) => setWithBrochures(e.target.checked)} /> Also send {brochures.length === 1 ? "the brochure" : `the ${brochures.length} brochures`} as documents</label>
      )}
      {channel === "email" && brochures.length > 0 && <p className="note">The brochure links are in the message.</p>}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={share} disabled={busy || (sends && !text.trim())}>{busy ? "Saving…" : sends ? "Send" : "Record"}</button>
    </Sheet>
  );
}
