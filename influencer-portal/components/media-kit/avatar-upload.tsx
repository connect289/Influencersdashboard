"use client";
import { Camera, Trash2 } from "lucide-react";
import Image from "next/image";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useAction } from "@/components/ui/use-action";
import { avatarUploadUrl, setAvatar } from "@/lib/actions/media-kit";
import { AVATAR_BUCKET, AVATAR_MAX_BYTES, AVATAR_TYPES } from "@/lib/media-kit/data";
import { createClient } from "@/lib/supabase/browser";

/** Profile photo: shown on the media kit and public page. Uploaded straight to the public avatars bucket. */
export function AvatarUpload({
  creatorId,
  current,
  name,
}: {
  creatorId: string;
  current: string | null;
  name: string;
}) {
  const t = useTranslations();
  const ref = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const { pending, run } = useAction();
  async function upload(file: File) {
    if (!(file.type in AVATAR_TYPES) || file.size > AVATAR_MAX_BYTES) {
      toast.error(t("mediaKit.errors.avatarType"));
      return;
    }
    setBusy(true);
    try {
      const signed = await avatarUploadUrl({
        creatorId,
        type: file.type as keyof typeof AVATAR_TYPES,
        size: file.size,
      });
      if (!signed.ok || !signed.data) {
        toast.error(signed.ok ? t("errors.generic") : signed.error);
        return;
      }
      const { error } = await createClient()
        .storage.from(AVATAR_BUCKET)
        .uploadToSignedUrl(signed.data.path, signed.data.token, file, { contentType: file.type });
      if (error) toast.error(t("kyc.errors.uploadFailed"));
      else run(() => setAvatar(creatorId, signed.data?.path ?? null));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="flex items-center gap-4">
      {current ? (
        <Image
          src={current}
          alt={t("mediaKit.avatarAlt", { name })}
          width={64}
          height={64}
          unoptimized
          className="size-16 rounded-full object-cover"
        />
      ) : (
        <div
          className="flex size-16 items-center justify-center rounded-full bg-surface-2 text-xl font-semibold text-muted"
          aria-hidden
        >
          {name.slice(0, 1).toUpperCase()}
        </div>
      )}
      <input
        ref={ref}
        type="file"
        accept={Object.keys(AVATAR_TYPES).join(",")}
        className="sr-only"
        aria-label={t("mediaKit.uploadAvatar")}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) void upload(f);
          e.target.value = "";
        }}
      />
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          size="sm"
          variant="secondary"
          disabled={busy || pending}
          onClick={() => ref.current?.click()}
        >
          <Camera />{" "}
          {busy
            ? t("kyc.uploading")
            : current
              ? t("mediaKit.changeAvatar")
              : t("mediaKit.uploadAvatar")}
        </Button>
        {current ? (
          <Button
            type="button"
            size="sm"
            variant="ghost"
            disabled={pending}
            onClick={() => run(() => setAvatar(creatorId, null))}
          >
            <Trash2 /> {t("common.remove")}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
