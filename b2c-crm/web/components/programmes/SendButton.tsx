"use client";
import { useState } from "react";
import { Send } from "lucide-react";
import type { Programme } from "@/lib/programmes";
import { ShareSheet } from "./ShareSheet";

/** Opens the share sheet for one programme or a comparison, from the Programme page opened for a lead. */
export function SendButton({ leadId, rows, firstName, counsellor, hasEmail, label }: { leadId: number; rows: Programme[]; firstName: string | null; counsellor: string | null; hasEmail: boolean; label: string }) {
  const [open, setOpen] = useState(false);
  const first = (firstName ?? "").trim().split(/\s+/)[0] || null;
  return (
    <>
      <button type="button" className="btn ghost sm" onClick={() => setOpen(true)}><Send className="icon s" aria-hidden />{label}</button>
      {open && <ShareSheet leadId={leadId} rows={rows} firstName={first} counsellor={counsellor} hasEmail={hasEmail} onDone={() => setOpen(false)} onClose={() => setOpen(false)} />}
    </>
  );
}
