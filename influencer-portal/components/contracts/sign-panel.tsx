"use client";
// OTP click-sign (spec 8.4): confirm each section, type the full legal name, accept the consent text, receive a
// one-time code on a channel set in settings, enter it to sign. The version and hash shown here are sent with the
// signature; if the contract changed in the meantime the database refuses it.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { requestSignCode, signContract } from "@/lib/actions/signing";

export interface SignPanelProps {
  contractId: string;
  versionId: string;
  sha256: string;
  sections: { key: string; number: number; title: string }[];
  consent: { version: number; body: string };
  channels: ("email" | "whatsapp")[];
  role: "creator" | "signatory";
}

export function SignPanel({ contractId, versionId, sha256, sections, consent, channels, role }: SignPanelProps) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [confirmed, setConfirmed] = useState<Set<string>>(new Set());
  const [name, setName] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [channel, setChannel] = useState(channels[0] ?? "email");
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const allConfirmed = sections.every((s) => confirmed.has(s.key));
  const ready = allConfirmed && name.trim().length >= 2 && agreed;

  if (channels.length === 0)
    return (
      <Card className="ring-2 ring-accent">
        <CardHeader title={t("contracts.sign.title")} description={t("contracts.sign.noChannel")} />
      </Card>
    );

  return (
    <Card className="ring-2 ring-accent">
      <CardHeader
        title={role === "signatory" ? t("contracts.sign.countersignTitle") : t("contracts.sign.title")}
        description={t("contracts.sign.hint")}
      />
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () => signContract({ contractId, versionId, sha256, name, consentVersion: consent.version, code }),
            () => router.refresh(),
          );
        }}
      >
        <fieldset className="flex flex-col gap-1">
          <legend className="mb-1 text-sm font-medium">
            {t("contracts.sign.sections", { done: confirmed.size, total: sections.length })}
          </legend>
          <div className="max-h-56 overflow-y-auto rounded-lg border border-line p-2">
            {sections.map((s) => (
              <label key={s.key} className="flex items-start gap-2 py-1 text-sm">
                <input
                  type="checkbox"
                  className="mt-1"
                  checked={confirmed.has(s.key)}
                  onChange={(e) =>
                    setConfirmed((prev) => {
                      const next = new Set(prev);
                      if (e.target.checked) next.add(s.key);
                      else next.delete(s.key);
                      return next;
                    })
                  }
                />
                <span>
                  {t("contracts.sign.readSection", { number: s.number })}{" "}
                  <a href={`#clause-${s.key}`} className="text-primary hover:underline">
                    {s.title}
                  </a>
                </span>
              </label>
            ))}
          </div>
        </fieldset>
        <Field id="sg-name" label={t("contracts.sign.name")} hint={t("contracts.sign.nameHint")} required>
          <Input
            id="sg-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoComplete="name"
            maxLength={160}
            required
          />
        </Field>
        <label className="flex items-start gap-2 rounded-lg bg-surface-2 p-3 text-sm">
          <input type="checkbox" className="mt-1" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} />
          <span>{consent.body}</span>
        </label>
        {channels.length > 1 ? (
          <fieldset className="flex flex-wrap gap-4 text-sm">
            <legend className="mb-1 text-sm font-medium">{t("contracts.sign.channel")}</legend>
            {channels.map((c) => (
              <label key={c} className="flex items-center gap-2">
                <input type="radio" name="sg-channel" checked={channel === c} onChange={() => setChannel(c)} />
                {t(`contracts.sign.channels.${c}`)}
              </label>
            ))}
          </fieldset>
        ) : null}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Button
            type="button"
            variant="secondary"
            disabled={!ready || pending}
            onClick={() =>
              run(
                () => requestSignCode({ contractId, channel }),
                (d) => setSentTo(d?.sentTo ?? null),
              )
            }
          >
            {sentTo ? t("contracts.sign.resend") : t("contracts.sign.sendCode")}
          </Button>
          {sentTo ? (
            <Field id="sg-code" label={t("contracts.sign.code", { to: sentTo })} className="flex-1">
              <Input
                id="sg-code"
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="\d{6}"
                required
              />
            </Field>
          ) : null}
        </div>
        {!ready ? <p className="text-xs text-muted">{t("contracts.sign.notReady")}</p> : null}
        <div className="flex justify-end">
          <Button type="submit" disabled={!ready || !sentTo || code.length !== 6 || pending}>
            {role === "signatory" ? t("contracts.sign.countersign") : t("contracts.sign.sign")}
          </Button>
        </div>
      </form>
    </Card>
  );
}
