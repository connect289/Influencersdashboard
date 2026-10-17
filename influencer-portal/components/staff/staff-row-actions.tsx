"use client";
import { MoreHorizontal } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { setStaffStatus, signOutStaffEverywhere } from "@/lib/actions/staff";
import type { ActionResult } from "@/lib/actions/result";
import { StaffDialog, type StaffFormValues } from "./staff-dialog";

type Pending = { kind: "suspend" | "reactivate" | "signout" } | null;

export function StaffRowActions({
  userId,
  values,
  status,
  isSelf,
  name,
}: {
  userId: string;
  values: StaffFormValues;
  status: string;
  isSelf: boolean;
  name: string;
}) {
  const t = useTranslations();
  const [confirm, setConfirm] = useState<Pending>(null);
  const [reason, setReason] = useState("");
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<ActionResult>) =>
    start(async () => {
      const r = await fn();
      if (r.ok) {
        toast.success(r.message ?? "");
        setConfirm(null);
        setReason("");
      } else toast.error(r.error);
    });
  return (
    <div className="flex justify-end gap-1">
      <StaffDialog
        invite={false}
        initial={values}
        trigger={
          <Button variant="ghost" size="sm">
            {t("common.edit")}
          </Button>
        }
      />
      {!isSelf ? (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" aria-label={t("staff.moreActions", { name })}>
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {status === "active" ? (
              <DropdownMenuItem onSelect={() => setConfirm({ kind: "suspend" })}>{t("staff.suspend")}</DropdownMenuItem>
            ) : (
              <DropdownMenuItem onSelect={() => setConfirm({ kind: "reactivate" })}>
                {t("staff.reactivate")}
              </DropdownMenuItem>
            )}
            <DropdownMenuItem onSelect={() => setConfirm({ kind: "signout" })}>
              {t("staff.signOutEverywhere")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      ) : null}
      <Dialog open={confirm !== null} onOpenChange={(o) => !o && setConfirm(null)}>
        {confirm ? (
          <DialogContent
            title={t(`staff.confirm.${confirm.kind}.title`, { name })}
            description={t(`staff.confirm.${confirm.kind}.body`)}
            closeLabel={t("common.close")}
          >
            <div className="flex flex-col gap-4">
              <Field id="reason" label={t("staff.fields.reason")} required>
                <Input id="reason" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} />
              </Field>
              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setConfirm(null)}>
                  {t("common.cancel")}
                </Button>
                <Button
                  variant={confirm.kind === "reactivate" ? "primary" : "danger"}
                  disabled={pending || reason.trim().length < 3}
                  onClick={() =>
                    run(() =>
                      confirm.kind === "signout"
                        ? signOutStaffEverywhere(userId, reason)
                        : setStaffStatus(userId, confirm.kind === "suspend" ? "suspended" : "active", reason),
                    )
                  }
                >
                  {t(`staff.confirm.${confirm.kind}.action`)}
                </Button>
              </div>
            </div>
          </DialogContent>
        ) : null}
      </Dialog>
    </div>
  );
}
