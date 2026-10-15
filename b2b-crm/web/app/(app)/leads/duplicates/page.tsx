import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/Card";
import { buttonClass } from "@/components/ui/Button";
import { requireAdmin } from "@/lib/auth";
import { leadDuplicates } from "@/lib/leads-data";
import { Duplicates } from "./Duplicates";

export const metadata: Metadata = { title: "Possible duplicates" };

/** M33b: leads that may be the same student (b2b.lead_duplicates). Merge or dismiss each pair. */
export default async function DuplicatesPage() {
  await requireAdmin();
  const pairs = await leadDuplicates();
  return (
    <>
      <PageHeader title="Possible duplicates" description="Live leads that share an email, a recorded phone number, or a name and city. Merging keeps one lead, fills its empty fields from the other, moves notes, tags and contacts, and records the other number so a new enquiry on it joins the kept lead."
        actions={<Link href="/leads" className={buttonClass("secondary", "sm")}><ArrowLeft className="size-3.5" /> Leads</Link>} />
      <Duplicates pairs={pairs} />
    </>
  );
}
