"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { newLead } from "../actions";

const OUTCOME_TEXT: Record<string, string> = {
  requested: "Sent to the master lead table. The lead comes back to you in under a minute.",
  reengaged: "This student was in nurture. They are yours now, marked hot.",
  yours: "This student is already yours.",
};

/** New lead, phone first (spec B5.2): duplicates are found before anything is created. */
export function NewLeadButton() {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn ghost sm" onClick={() => setOpen(true)}><Plus className="icon s" aria-hidden />New lead</button>
      {open && <NewLeadSheet onClose={() => setOpen(false)} />}
    </>
  );
}

function NewLeadSheet({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  function submit(form: FormData) {
    const v = (k: string) => String(form.get(k) ?? "").trim();
    start(async () => {
      const r = await newLead({ phone: v("phone"), name: v("name"), email: v("email"), course: v("course"), city: v("city"), notes: v("notes") });
      if (!r.ok) return setError(r.error);
      const o = r.data?.outcome ?? "requested";
      if (o === "with_partner") return setError("This student is already with an admission partner. Eduwit cannot take them in the B2C CRM.");
      if (o === "with_counsellor") return setError(`This student is already with ${r.data?.owner ?? "another counsellor"}. Ask them or the Admin.`);
      toast.success(OUTCOME_TEXT[o] ?? "Saved.");
      onClose();
      if (r.data?.lead_id) router.push(`/s/leads/${r.data.lead_id}`);
      else router.refresh();
    });
  }
  return (
    <Sheet title="New lead" onClose={onClose}>
      <p className="note">Phone first: we check the master lead table so a student is never created twice.</p>
      <form action={submit} className="stack">
        <label className="field"><span>Phone (required)</span><input className="input" name="phone" inputMode="tel" required placeholder="98765 43210" /></label>
        <label className="field"><span>Name</span><input className="input" name="name" maxLength={120} /></label>
        <label className="field"><span>Email</span><input className="input" name="email" type="email" maxLength={254} /></label>
        <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>Programme</span><input className="input" name="course" maxLength={120} placeholder="Online MBA" /></label>
          <label className="field"><span>City</span><input className="input" name="city" maxLength={80} /></label>
        </div>
        <label className="field"><span>Notes</span><textarea className="input" name="notes" maxLength={500} /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Checking…" : "Check and create"}</button>
      </form>
    </Sheet>
  );
}
