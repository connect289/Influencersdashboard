"use client";
// The staff brief editor: the working copy, saved as you go and published as a new version for the creator.
import { Paperclip, Send, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { briefAssetUploadUrl, publishBrief, saveBrief } from "@/lib/actions/content";
import { briefContent, type BriefContent } from "@/lib/content/brief";
import { createClient } from "@/lib/supabase/browser";
import { BriefFields, cleanShared } from "./brief-fields";
import { ListEditor } from "./list-editor";

const MAX_ASSET_BYTES = 100 * 1024 * 1024;

function clean(v: BriefContent): BriefContent {
  const lines = (x: readonly string[]) => x.map((s) => s.trim()).filter(Boolean);
  return {
    ...cleanShared(v),
    approved_claims: lines(v.approved_claims),
    assets: v.assets.filter((a) => a.label.trim()),
  };
}

export function BriefEditor({
  briefId,
  initial,
  published,
  unpublishedChanges,
}: {
  briefId: string;
  initial: BriefContent;
  published: boolean;
  /** The saved working copy differs from the published version. */
  unpublishedChanges: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState<BriefContent>(initial);
  const [saved, setSaved] = useState(JSON.stringify(initial));
  const [note, setNote] = useState("");
  const [open, setOpen] = useState(false);
  const [uploading, setUploading] = useState(false);
  const file = useRef<HTMLInputElement>(null);
  const dirty = JSON.stringify(v) !== saved;

  function save() {
    const parsed = briefContent.safeParse(clean(v));
    if (!parsed.success) {
      toast.error(t("content.errors.briefInvalid"));
      return;
    }
    run(
      () => saveBrief({ briefId, content: parsed.data }),
      () => {
        setV(parsed.data);
        setSaved(JSON.stringify(parsed.data));
        router.refresh();
      },
    );
  }

  async function upload(f: File) {
    if (f.size > MAX_ASSET_BYTES) {
      toast.error(t("content.errors.tooLarge", { mb: 100 }));
      return;
    }
    setUploading(true);
    try {
      const signed = await briefAssetUploadUrl({ briefId, fileName: f.name, size: f.size });
      if (!signed.ok || !signed.data) {
        toast.error(signed.ok ? t("errors.generic") : signed.error);
        return;
      }
      const { error } = await createClient()
        .storage.from("inf-briefs")
        .uploadToSignedUrl(signed.data.path, signed.data.token, f, { contentType: f.type });
      if (error) toast.error(t("content.errors.uploadFailed"));
      else {
        const path = signed.data.path;
        setV((x) => ({ ...x, assets: [...x.assets, { label: f.name.slice(0, 300), path }] }));
        toast.success(t("content.brief.assetAdded"));
      }
    } finally {
      setUploading(false);
      if (file.current) file.current.value = "";
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {unpublishedChanges && !dirty ? (
        <Banner tone="warning">{t("content.brief.unpublished")}</Banner>
      ) : null}
      <Card>
        <CardHeader
          title={t("content.brief.contentTitle")}
          description={t("content.brief.contentHint")}
        />
        <BriefFields value={v} onChange={setV} />
      </Card>
      <Card>
        <CardHeader
          title={t("content.brief.claimsTitle")}
          description={t("content.brief.claimsHint")}
        />
        <ListEditor
          id="bf-claims"
          label={t("content.brief.approvedClaims")}
          value={v.approved_claims}
          max={100}
          onChange={(x) => setV({ ...v, approved_claims: x })}
        />
        {v.banned_claims.length ? (
          <div className="mt-4">
            <p className="text-sm font-medium">{t("content.brief.bannedClaims")}</p>
            <p className="mb-2 text-xs text-muted">{t("content.brief.bannedHint")}</p>
            <ul className="flex flex-wrap gap-1.5">
              {v.banned_claims.map((c) => (
                <li key={c} className="rounded-full bg-danger-soft px-2 py-0.5 text-xs text-danger">
                  {c}
                </li>
              ))}
            </ul>
          </div>
        ) : null}
      </Card>
      <Card>
        <CardHeader
          title={t("content.brief.assets")}
          description={t("content.brief.assetsHint")}
          actions={
            <>
              <input
                ref={file}
                type="file"
                className="sr-only"
                id="bf-asset"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) void upload(f);
                }}
              />
              <Button
                type="button"
                variant="secondary"
                size="sm"
                disabled={uploading}
                onClick={() => file.current?.click()}
              >
                <Paperclip />{" "}
                {uploading ? t("content.upload.uploading") : t("content.brief.addAsset")}
              </Button>
            </>
          }
        />
        {v.assets.length === 0 ? (
          <p className="text-sm text-muted">{t("content.brief.noAssets")}</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {v.assets.map((a, i) => (
              <li key={a.path} className="flex gap-2">
                <Input
                  aria-label={t("content.brief.assetLabel")}
                  value={a.label}
                  maxLength={300}
                  onChange={(e) =>
                    setV({
                      ...v,
                      assets: v.assets.map((x, j) =>
                        j === i ? { ...x, label: e.target.value } : x,
                      ),
                    })
                  }
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={t("common.remove")}
                  onClick={() => setV({ ...v, assets: v.assets.filter((_, j) => j !== i) })}
                >
                  <X />
                </Button>
              </li>
            ))}
          </ul>
        )}
      </Card>
      <div className="sticky bottom-20 z-10 flex flex-wrap items-center justify-end gap-2 rounded-xl bg-surface/95 p-2 ring-1 ring-line backdrop-blur md:bottom-4">
        {dirty ? (
          <span className="mr-auto text-sm text-muted">{t("content.brief.unsaved")}</span>
        ) : null}
        <Button type="button" variant="secondary" disabled={pending || !dirty} onClick={save}>
          {t("common.save")}
        </Button>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button type="button" disabled={pending || dirty}>
              <Send /> {published ? t("content.brief.publishNew") : t("content.brief.publish")}
            </Button>
          </DialogTrigger>
          <DialogContent
            title={published ? t("content.brief.publishNew") : t("content.brief.publish")}
            description={t("content.brief.publishHint")}
            closeLabel={t("common.close")}
          >
            <form
              className="flex flex-col gap-4"
              onSubmit={(e) => {
                e.preventDefault();
                run(
                  () => publishBrief({ briefId, note }),
                  () => {
                    setOpen(false);
                    setNote("");
                    router.refresh();
                  },
                );
              }}
            >
              <Field
                id="bf-note"
                label={t("content.brief.versionNote")}
                hint={t("content.brief.versionNoteHint")}
              >
                <Input
                  id="bf-note"
                  maxLength={500}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              </Field>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" onClick={() => setOpen(false)}>
                  {t("common.cancel")}
                </Button>
                <Button type="submit" disabled={pending}>
                  {t("content.brief.publishConfirm")}
                </Button>
              </div>
            </form>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  );
}
