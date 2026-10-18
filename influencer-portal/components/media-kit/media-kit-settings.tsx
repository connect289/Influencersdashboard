"use client";
import { Copy, Download, ExternalLink } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveMediaKitSettings } from "@/lib/actions/media-kit";

/** The creator's media-kit controls: public page on/off, show rates, share link, PDF download. */
export function MediaKitSettings({
  creatorId,
  handle,
  publicPage,
  showRates,
  siteUrl,
  approved,
}: {
  creatorId: string;
  handle: string;
  publicPage: boolean;
  showRates: boolean;
  siteUrl: string;
  approved: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [pub, setPub] = useState(publicPage);
  const [rates, setRates] = useState(showRates);
  const link = `${siteUrl.replace(/\/$/, "")}/m/${handle}`;
  return (
    <Card>
      <CardHeader title={t("mediaKit.shareTitle")} description={t("mediaKit.shareHint")} />
      <div className="flex flex-col gap-3">
        <SwitchField
          id="mk-public"
          checked={pub}
          disabled={pending}
          onCheckedChange={(c) => {
            setPub(c);
            run(() => saveMediaKitSettings(creatorId, c, rates));
          }}
          label={t("mediaKit.publicPage")}
          hint={approved ? t("mediaKit.publicPageHint") : t("mediaKit.publicPageApproval")}
        />
        <SwitchField
          id="mk-rates"
          checked={rates}
          disabled={pending}
          onCheckedChange={(c) => {
            setRates(c);
            run(() => saveMediaKitSettings(creatorId, pub, c));
          }}
          label={t("mediaKit.showRates")}
          hint={t("mediaKit.showRatesHint")}
        />
        <div className="flex flex-wrap gap-2 pt-2">
          <Button asChild>
            <a href={`/api/media-kit/${creatorId}`}>
              <Download /> {t("mediaKit.downloadPdf")}
            </a>
          </Button>
          {pub && approved ? (
            <>
              <Button
                variant="secondary"
                onClick={() => {
                  void navigator.clipboard.writeText(link).then(() => toast.success(t("mediaKit.copied")));
                }}
              >
                <Copy /> {t("mediaKit.copyLink")}
              </Button>
              <Button asChild variant="ghost">
                <a href={link} target="_blank" rel="noopener">
                  <ExternalLink /> {t("mediaKit.openPublic")}
                </a>
              </Button>
            </>
          ) : null}
        </div>
        {pub && approved ? <p className="text-xs break-all text-muted">{link}</p> : null}
      </div>
    </Card>
  );
}
