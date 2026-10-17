"use client";
// The creator submits a concept (idea, script or storyboard) or a draft (the edit and caption that will be posted).
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { submitWork } from "@/lib/actions/content";
import { UploadField } from "./upload-field";
import type { Uploaded } from "./uploader";

export function SubmitForm({ deliverableId, kind }: { deliverableId: string; kind: "concept" | "draft" }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [body, setBody] = useState("");
  const [files, setFiles] = useState<Uploaded[]>([]);
  const [linkUrl, setLinkUrl] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const empty = !body.trim() && files.length === 0 && !linkUrl.trim();
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => submitWork({ deliverableId, kind, body, files, linkUrl, note }),
          () => {
            setBody("");
            setFiles([]);
            setLinkUrl("");
            setNote("");
            router.refresh();
          },
        );
      }}
    >
      <Field id="sub-body" label={t(`content.submit.body.${kind}`)} hint={t(`content.submit.bodyHint.${kind}`)}>
        <Textarea id="sub-body" rows={6} maxLength={20000} value={body} onChange={(e) => setBody(e.target.value)} />
      </Field>
      <UploadField
        id="sub-files"
        deliverableId={deliverableId}
        value={files}
        onChange={setFiles}
        max={10}
        label={t("content.submit.files")}
        onBusy={setBusy}
      />
      <Field id="sub-link" label={t("content.submit.link")} hint={t("content.submit.linkHint")}>
        <Input
          id="sub-link"
          inputMode="url"
          placeholder="https://"
          maxLength={1000}
          value={linkUrl}
          onChange={(e) => setLinkUrl(e.target.value)}
        />
      </Field>
      <Field id="sub-note" label={t("content.submit.note")}>
        <Input id="sub-note" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <Button type="submit" className="self-start" disabled={pending || busy || empty}>
        {t(`content.submit.send.${kind}`)}
      </Button>
    </form>
  );
}
