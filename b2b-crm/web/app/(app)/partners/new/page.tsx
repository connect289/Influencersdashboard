import type { Metadata } from "next";
import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { PartnerForm } from "../PartnerForm";

export const metadata: Metadata = { title: "Add partner" };

export default async function NewPartnerPage() {
  await requireAdmin();
  return (
    <>
      <Link href="/partners" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Partners</Link>
      <PageHeader title="Add partner" description="The partner starts in onboarding with its live switch off. Nothing is sent to it until you switch it on." />
      <PartnerForm />
    </>
  );
}
