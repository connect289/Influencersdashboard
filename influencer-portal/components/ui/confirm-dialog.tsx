"use client";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

/**
 * Confirmation for destructive or recorded actions. With `reasonLabel`, a reason of at least 3 characters is required
 * and passed to `onConfirm`. Resolve `onConfirm` to true to close.
 */
export function ConfirmDialog({
  trigger,
  title,
  description,
  actionLabel,
  reasonLabel,
  danger = true,
  pending,
  defaultOpen = false,
  onClose,
  onConfirm,
}: {
  trigger: ReactNode;
  title: string;
  description?: string;
  actionLabel: string;
  reasonLabel?: string;
  danger?: boolean;
  pending?: boolean;
  /** Open on mount (e.g. when a menu item asks for confirmation). */
  defaultOpen?: boolean;
  onClose?: () => void;
  onConfirm: (reason: string, close: () => void) => void;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(defaultOpen);
  const [reason, setReason] = useState("");
  const close = () => {
    setOpen(false);
    setReason("");
    onClose?.();
  };
  return (
    <Dialog open={open} onOpenChange={(o) => (o ? setOpen(true) : close())}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent title={title} description={description} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            // The dialog renders in a portal but React still bubbles its submit to any form around the trigger.
            e.stopPropagation();
            onConfirm(reason.trim(), close);
          }}
        >
          {reasonLabel ? (
            <Field id="confirm-reason" label={reasonLabel} required>
              <Input id="confirm-reason" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} />
            </Field>
          ) : null}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={close}>
              {t("common.cancel")}
            </Button>
            <Button
              type="submit"
              variant={danger ? "danger" : "primary"}
              disabled={pending || (reasonLabel !== undefined && reason.trim().length < 3)}
            >
              {actionLabel}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
