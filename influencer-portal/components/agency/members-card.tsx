"use client";
import { Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { addAgencyMember, removeAgencyMember } from "@/lib/actions/agency";

export interface MemberRow {
  id: string;
  full_name: string;
  email: string;
  role: string;
  user_id: string | null;
}

export function MembersCard({
  agencyId,
  members,
  canManage,
  currentUserId,
}: {
  agencyId: string;
  members: MemberRow[];
  canManage: boolean;
  currentUserId?: string;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const { pending, run } = useAction();
  const [v, setV] = useState({ fullName: "", email: "", role: "member" as "owner" | "member" });
  const add = canManage ? (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="secondary">
          <Plus /> {t("agencies.members.add")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("agencies.members.add")}
        description={t("agencies.members.addHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => addAgencyMember({ agencyId, ...v }),
              () => {
                setOpen(false);
                setV({ fullName: "", email: "", role: "member" });
              },
            );
          }}
        >
          <Field id="am-name" label={t("agencies.members.name")} required>
            <Input
              id="am-name"
              value={v.fullName}
              onChange={(e) => setV({ ...v, fullName: e.target.value })}
              required
              maxLength={120}
            />
          </Field>
          <Field id="am-email" label={t("agencies.members.email")} required>
            <Input
              id="am-email"
              type="email"
              value={v.email}
              onChange={(e) => setV({ ...v, email: e.target.value })}
              required
              maxLength={254}
            />
          </Field>
          <Field id="am-role" label={t("agencies.members.role")}>
            <Select
              id="am-role"
              value={v.role}
              onChange={(e) => setV({ ...v, role: e.target.value as "owner" | "member" })}
            >
              <option value="member">{t("agencies.members.roles.member")}</option>
              <option value="owner">{t("agencies.members.roles.owner")}</option>
            </Select>
          </Field>
          <Button type="submit" disabled={pending || !v.fullName || !v.email}>
            {t("agencies.members.sendInvite")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  ) : null;
  return (
    <Card>
      <CardHeader
        title={t("agencies.members.title")}
        description={t("agencies.members.hint")}
        actions={add}
      />
      {members.length === 0 ? (
        <EmptyState title={t("agencies.members.empty")} />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {members.map((m) => (
            <li key={m.id} className="flex items-center gap-3 py-3">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{m.full_name}</p>
                <p className="truncate text-xs text-muted">{m.email}</p>
              </div>
              {m.role === "owner" ? (
                <Badge family="success">{t("agencies.members.roles.owner")}</Badge>
              ) : null}
              {!m.user_id ? (
                <Badge family="attention">{t("agencies.members.invited")}</Badge>
              ) : null}
              {canManage && m.user_id !== currentUserId ? (
                <ConfirmDialog
                  title={t("agencies.members.removeTitle", { name: m.full_name })}
                  description={t("agencies.members.removeBody")}
                  actionLabel={t("common.remove")}
                  pending={pending}
                  onConfirm={(_, close) => run(() => removeAgencyMember(m.id), close)}
                  trigger={
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={t("agencies.members.removeOne", { name: m.full_name })}
                    >
                      <Trash2 />
                    </Button>
                  }
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
