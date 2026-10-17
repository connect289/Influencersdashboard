"use client";
// Picks and uploads files for a deliverable, one at a time with progress; large videos resume after a dropped
// connection. The parent keeps the list of uploaded files.
import { FileText, Film, ImageIcon, Paperclip, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { UPLOAD_TYPES, type UploadType } from "@/lib/content/schemas";
import { formatNumber } from "@/lib/format";
import { uploadDeliverableFile, type Uploaded } from "./uploader";

export function fileIcon(type: string) {
  if (type.startsWith("video/")) return <Film className="size-4" aria-hidden />;
  if (type.startsWith("image/")) return <ImageIcon className="size-4" aria-hidden />;
  return <FileText className="size-4" aria-hidden />;
}

const mb = (bytes: number) => `${formatNumber(Math.max(1, Math.round(bytes / (1024 * 1024))))} MB`;

export function UploadField({
  id,
  deliverableId,
  value,
  onChange,
  max,
  accept = UPLOAD_TYPES,
  label,
  onBusy,
}: {
  id: string;
  deliverableId: string;
  value: Uploaded[];
  onChange: (v: Uploaded[]) => void;
  max: number;
  accept?: readonly UploadType[];
  label: string;
  onBusy?: (busy: boolean) => void;
}) {
  const t = useTranslations();
  const input = useRef<HTMLInputElement>(null);
  const abort = useRef<AbortController | null>(null);
  const [progress, setProgress] = useState<{ name: string; fraction: number } | null>(null);

  async function add(files: FileList) {
    const list = [...files].slice(0, max - value.length);
    let next = value;
    onBusy?.(true);
    try {
      for (const f of list) {
        if (!(accept as readonly string[]).includes(f.type)) {
          toast.error(t("content.errors.fileType", { name: f.name }));
          continue;
        }
        abort.current = new AbortController();
        setProgress({ name: f.name, fraction: 0 });
        try {
          const up = await uploadDeliverableFile(
            deliverableId,
            f,
            f.type as UploadType,
            (fraction) => setProgress({ name: f.name, fraction }),
            abort.current.signal,
          );
          next = [...next, up];
          onChange(next);
        } catch (e) {
          if (abort.current.signal.aborted) toast.info(t("content.upload.paused"));
          else
            toast.error(
              e instanceof Error && e.message && !/^(create|patch|sign)\b/.test(e.message)
                ? e.message
                : t("content.errors.uploadFailed"),
            );
        }
      }
    } finally {
      setProgress(null);
      abort.current = null;
      onBusy?.(false);
      if (input.current) input.current.value = "";
    }
  }

  return (
    <div className="flex flex-col gap-2">
      <span className="text-sm font-medium" id={`${id}-label`}>
        {label}
      </span>
      {value.length ? (
        <ul className="flex flex-col gap-1.5" aria-labelledby={`${id}-label`}>
          {value.map((f) => (
            <li key={f.path} className="flex items-center gap-2 rounded-lg bg-surface-2 px-2 py-1.5 text-sm">
              {fileIcon(f.type)}
              <span className="min-w-0 flex-1 truncate">{f.name}</span>
              <span className="text-xs text-muted">{mb(f.size)}</span>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                aria-label={t("common.remove")}
                onClick={() => onChange(value.filter((x) => x.path !== f.path))}
              >
                <X />
              </Button>
            </li>
          ))}
        </ul>
      ) : null}
      {progress ? (
        <div className="flex flex-col gap-1" role="status">
          <div className="flex items-center justify-between text-xs text-muted">
            <span className="truncate">{t("content.upload.uploadingFile", { name: progress.name })}</span>
            <span>{Math.round(progress.fraction * 100)}%</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-surface-2">
            <div
              className="h-full bg-primary transition-[width]"
              style={{ width: `${String(Math.round(progress.fraction * 100))}%` }}
            />
          </div>
          <Button
            type="button"
            variant="link"
            size="sm"
            className="self-start px-0"
            onClick={() => abort.current?.abort()}
          >
            {t("content.upload.pause")}
          </Button>
        </div>
      ) : null}
      <input
        ref={input}
        id={id}
        type="file"
        multiple={max > 1}
        accept={accept.join(",")}
        className="sr-only"
        onChange={(e) => {
          if (e.target.files?.length) void add(e.target.files);
        }}
      />
      {value.length < max && !progress ? (
        <Button
          type="button"
          variant="secondary"
          size="sm"
          className="self-start"
          onClick={() => input.current?.click()}
        >
          <Paperclip /> {t("content.upload.add")}
        </Button>
      ) : null}
      <p className="text-xs text-muted">{t("content.upload.hint")}</p>
    </div>
  );
}
