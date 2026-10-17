"use client";
// Generate a contract from a deal: pick the template, who is paid (the creator, or an agency the creator allowed to
// negotiate and sign), the dates and the stamp duty reference. Every number comes from the deal's terms in force.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { createContract } from "@/lib/actions/contracts";

export function NewContractForm({
  dealId,
  templates,
  defaultTemplateId,
  agencies,
  parent,
  startsOn,
  endsOn,
  renewal,
}: {
  dealId: string;
  templates: { id: string; name: string }[];
  defaultTemplateId: string;
  agencies: { id: string; name: string }[];
  parent: { id: string; number: string } | null;
  startsOn: string;
  endsOn: string | null;
  /** The deal renews an earlier one: the contract is a renewal. */
  renewal: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [templateId, setTemplateId] = useState(defaultTemplateId);
  const [payee, setPayee] = useState("");
  const [kind, setKind] = useState<"original" | "renewal">(renewal ? "renewal" : "original");
  const [effectiveOn, setEffectiveOn] = useState(startsOn);
  const [expiresOn, setExpiresOn] = useState(endsOn ?? "");
  const [stamp, setStamp] = useState("");
  return (
    <Card className="max-w-2xl">
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(
            () =>
              createContract({
                dealId,
                templateId,
                payeeAgencyId: payee || null,
                parentContractId: parent?.id ?? null,
                kind,
                effectiveOn,
                expiresOn,
                stampDutyReference: stamp,
              }),
            (d) => {
              if (d) router.push(`/admin/contracts/${d.id}`);
            },
          );
        }}
      >
        {parent ? (
          <Banner tone="info">{t("contracts.new.amendmentOf", { number: parent.number })}</Banner>
        ) : null}
        <Field id="nc-template" label={t("contracts.new.template")} required>
          <Select
            id="nc-template"
            value={templateId}
            onChange={(e) => setTemplateId(e.target.value)}
            required
          >
            {templates.map((tp) => (
              <option key={tp.id} value={tp.id}>
                {tp.name}
              </option>
            ))}
          </Select>
        </Field>
        {parent ? null : (
          <Field id="nc-kind" label={t("contracts.new.kind")}>
            <Select
              id="nc-kind"
              value={kind}
              onChange={(e) => setKind(e.target.value as "original" | "renewal")}
            >
              <option value="original">{t("contracts.kinds.original")}</option>
              <option value="renewal">{t("contracts.kinds.renewal")}</option>
            </Select>
          </Field>
        )}
        <Field id="nc-payee" label={t("contracts.new.payee")} hint={t("contracts.new.payeeHint")}>
          <Select id="nc-payee" value={payee} onChange={(e) => setPayee(e.target.value)}>
            <option value="">{t("contracts.new.payeeCreator")}</option>
            {agencies.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field id="nc-eff" label={t("contracts.new.effectiveOn")}>
            <Input
              id="nc-eff"
              type="date"
              value={effectiveOn}
              onChange={(e) => setEffectiveOn(e.target.value)}
            />
          </Field>
          <Field id="nc-exp" label={t("contracts.new.expiresOn")}>
            <Input
              id="nc-exp"
              type="date"
              value={expiresOn}
              onChange={(e) => setExpiresOn(e.target.value)}
            />
          </Field>
        </div>
        <Field
          id="nc-stamp"
          label={t("contracts.new.stampDuty")}
          hint={t("contracts.new.stampDutyHint")}
        >
          <Input
            id="nc-stamp"
            value={stamp}
            onChange={(e) => setStamp(e.target.value)}
            maxLength={120}
          />
        </Field>
        <div className="flex justify-end">
          <Button type="submit" disabled={pending || !templateId}>
            {t("contracts.new.generate")}
          </Button>
        </div>
      </form>
    </Card>
  );
}
