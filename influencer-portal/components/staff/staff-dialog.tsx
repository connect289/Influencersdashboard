"use client";
import { useTranslations } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { saveStaff } from "@/lib/actions/staff";
import { ROLE_LABELS, STAFF_ROLES, type StaffRole } from "@/lib/auth/permissions";

export interface StaffFormValues {
  email: string;
  fullName: string;
  roles: StaffRole[];
  isSignatory: boolean;
  designation: string;
}

export function StaffDialog({
  initial,
  invite,
  trigger,
}: {
  initial?: StaffFormValues;
  invite: boolean;
  trigger: React.ReactNode;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const [v, setV] = useState<StaffFormValues>(
    initial ?? { email: "", fullName: "", roles: [], isSignatory: false, designation: "" },
  );
  const [pending, start] = useTransition();
  const toggle = (r: StaffRole) =>
    setV((x) => ({ ...x, roles: x.roles.includes(r) ? x.roles.filter((y) => y !== r) : [...x.roles, r] }));
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent
        title={invite ? t("staff.inviteTitle") : t("staff.editTitle")}
        description={invite ? t("staff.inviteHint") : undefined}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            start(async () => {
              const r = await saveStaff(v, invite);
              if (r.ok) {
                toast.success(r.message ?? "");
                setOpen(false);
              } else toast.error(r.error);
            });
          }}
        >
          <Field id="staff-name" label={t("staff.fields.name")} required>
            <Input
              id="staff-name"
              value={v.fullName}
              onChange={(e) => setV({ ...v, fullName: e.target.value })}
              required
              maxLength={120}
            />
          </Field>
          <Field id="staff-email" label={t("staff.fields.email")} required>
            <Input
              id="staff-email"
              type="email"
              value={v.email}
              onChange={(e) => setV({ ...v, email: e.target.value })}
              required
              disabled={!invite}
            />
          </Field>
          <fieldset>
            <legend className="mb-1.5 text-sm font-medium">{t("staff.fields.roles")}</legend>
            <div className="flex flex-col gap-2">
              {STAFF_ROLES.map((r) => (
                <label key={r} className="flex items-start gap-2 text-sm">
                  <input
                    type="checkbox"
                    className="mt-0.5 size-4 accent-[var(--primary)]"
                    checked={v.roles.includes(r)}
                    onChange={() => toggle(r)}
                  />
                  <span>
                    <span className="font-medium">{ROLE_LABELS[r]}</span>
                    <span className="block text-xs text-muted">{t(`roles.descriptions.${r}`)}</span>
                  </span>
                </label>
              ))}
            </div>
          </fieldset>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              className="size-4 accent-[var(--primary)]"
              checked={v.isSignatory}
              onChange={(e) => setV({ ...v, isSignatory: e.target.checked })}
            />
            {t("staff.fields.signatory")}
          </label>
          {v.isSignatory ? (
            <Field id="staff-designation" label={t("staff.fields.designation")} required>
              <Input
                id="staff-designation"
                value={v.designation}
                onChange={(e) => setV({ ...v, designation: e.target.value })}
                maxLength={120}
              />
            </Field>
          ) : null}
          <Button type="submit" disabled={pending || v.roles.length === 0 || !v.fullName || !v.email}>
            {invite ? t("staff.sendInvite") : t("common.save")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
