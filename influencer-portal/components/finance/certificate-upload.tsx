"use client";
// Finance uploads a creator's Form 16A for a quarter (PDF, straight to the private bucket), then records it.
import { FileUp } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { certificateUploadUrl, recordCertificate } from "@/lib/actions/payouts";
import { createClient } from "@/lib/supabase/browser";

export function CertificateUpload({
  creatorId,
  fy,
  quarter,
  replace,
}: {
  creatorId: string;
  fy: string;
  quarter: "Q1" | "Q2" | "Q3" | "Q4";
  replace: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  async function upload(file: File) {
    if (file.type !== "application/pdf" || file.size > 10 * 1024 * 1024) {
      toast.error(t("finance.tds.pdfOnly"));
      return;
    }
    setBusy(true);
    try {
      const signed = await certificateUploadUrl({ creatorId, fy, quarter, size: file.size });
      if (!signed.ok || !signed.data) {
        toast.error(signed.ok ? t("errors.generic") : signed.error);
        return;
      }
      const { error } = await createClient()
        .storage.from("inf-documents")
        .uploadToSignedUrl(signed.data.path, signed.data.token, file, { contentType: "application/pdf" });
      if (error) {
        toast.error(t("finance.tds.uploadFailed"));
        return;
      }
      const r = await recordCertificate({ creatorId, fy, quarter, filePath: signed.data.path });
      if (r.ok) {
        toast.success(r.message ?? "");
        router.refresh();
      } else toast.error(r.error);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <input
        ref={input}
        type="file"
        accept="application/pdf"
        className="sr-only"
        aria-label={t("finance.tds.upload")}
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void upload(f);
        }}
      />
      <Button
        size="sm"
        variant={replace ? "ghost" : "secondary"}
        disabled={busy}
        onClick={() => input.current?.click()}
      >
        <FileUp /> {replace ? t("finance.tds.replace") : t("finance.tds.upload")}
      </Button>
    </>
  );
}
