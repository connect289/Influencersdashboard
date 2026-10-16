"use client";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { saveAgency } from "@/lib/actions/agency";

export interface AgencyFormValues {
  id?: string;
  name: string;
  legalName: string;
  email: string;
  phone: string;
  gstin: string;
  notes: string;
}

const EMPTY: AgencyFormValues = { name: "", legalName: "", email: "", phone: "", gstin: "", notes: "" };

export function AgencyDialog({ initial, trigger }: { initial?: AgencyFormValues; trigger: ReactNode }) {
  const t = useTranslations();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [v, setV] = useState<AgencyFormValues>(initial ?? EMPTY);
  const { pending, run } = useAction();
  const set = <K extends keyof AgencyFormValues>(k: K, value: AgencyFormValues[K]) =>
    setV((x) => ({ ...x, [k]: value }));
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent title={initial ? t("agencies.edit") : t("agencies.add")} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => saveAgency(v),
              (data) => {
                setOpen(false);
                if (!initial && data) router.push(`/admin/agencies/${data.id}`);
              },
            );
          }}
        >
          <Field id="ag-name" label={t("agencies.fields.name")} required>
            <Input
              id="ag-name"
              value={v.name}
              onChange={(e) => set("name", e.target.value)}
              required
              minLength={2}
              maxLength={120}
            />
          </Field>
          <Field id="ag-legal" label={t("agencies.fields.legalName")}>
            <Input
              id="ag-legal"
              value={v.legalName}
              onChange={(e) => set("legalName", e.target.value)}
              maxLength={160}
            />
          </Field>
          <div className="grid gap-4 md:grid-cols-2">
            <Field id="ag-email" label={t("agencies.fields.email")}>
              <Input
                id="ag-email"
                type="email"
                value={v.email}
                onChange={(e) => set("email", e.target.value)}
                maxLength={254}
              />
            </Field>
            <Field id="ag-phone" label={t("agencies.fields.phone")}>
              <Input
                id="ag-phone"
                type="tel"
                value={v.phone}
                onChange={(e) => set("phone", e.target.value)}
                maxLength={20}
              />
            </Field>
          </div>
          <Field id="ag-gstin" label={t("agencies.fields.gstin")}>
            <Input
              id="ag-gstin"
              value={v.gstin}
              onChange={(e) => set("gstin", e.target.value.toUpperCase())}
              maxLength={15}
              spellCheck={false}
            />
          </Field>
          <Field id="ag-notes" label={t("agencies.fields.notes")}>
            <Textarea id="ag-notes" value={v.notes} onChange={(e) => set("notes", e.target.value)} maxLength={2000} />
          </Field>
          <Button type="submit" disabled={pending || v.name.trim().length < 2}>
            {t("common.save")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
