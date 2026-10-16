"use client";
import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { Banner } from "@/components/ui/states";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { SubmitButton } from "@/components/ui/submit-button";
import {
  creatorSendOtp,
  creatorVerifyOtp,
  requestPasswordLink,
  sendStaffCode,
  setNewPassword,
  staffSignIn,
  verifyStaffCode,
  type FormState,
} from "@/app/(auth)/actions";

function Messages({ state }: { state: FormState }) {
  if (state?.error) return <Banner tone="danger">{state.error}</Banner>;
  if (state?.notice) return <Banner tone="success">{state.notice}</Banner>;
  return null;
}

export function CreatorEmailForm({ next }: { next: string }) {
  const t = useTranslations();
  const [state, action] = useActionState(creatorSendOtp, undefined);
  return (
    <form action={action} className="flex flex-col gap-4" noValidate>
      <Messages state={state} />
      <input type="hidden" name="next" value={next} />
      <Field id="email" label={t("auth.fields.email")} hint={t("auth.creator.emailHint")}>
        <Input id="email" name="email" type="email" autoComplete="email" inputMode="email" required aria-describedby="email-hint" />
      </Field>
      <SubmitButton block pendingLabel={t("auth.creator.sending")}>{t("auth.creator.sendCode")}</SubmitButton>
    </form>
  );
}

export function CreatorCodeForm({ next }: { next: string }) {
  const t = useTranslations();
  const [state, action] = useActionState(creatorVerifyOtp, undefined);
  return (
    <form action={action} className="flex flex-col gap-4">
      <Messages state={state} />
      <input type="hidden" name="next" value={next} />
      <Field id="code" label={t("auth.fields.code")}>
        <Input id="code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6,8}" maxLength={8} required className="text-center text-xl tracking-[0.4em]" />
      </Field>
      <SubmitButton block pendingLabel={t("auth.checking")}>{t("auth.continue")}</SubmitButton>
    </form>
  );
}

export function StaffPasswordForm({ next }: { next: string }) {
  const t = useTranslations();
  const [state, action] = useActionState(staffSignIn, undefined);
  return (
    <form action={action} className="flex flex-col gap-4">
      <Messages state={state} />
      <input type="hidden" name="next" value={next} />
      <Field id="email" label={t("auth.fields.workEmail")}>
        <Input id="email" name="email" type="email" autoComplete="username" required />
      </Field>
      <Field id="password" label={t("auth.fields.password")}>
        <Input id="password" name="password" type="password" autoComplete="current-password" required />
      </Field>
      <SubmitButton block pendingLabel={t("auth.signingIn")}>{t("auth.signIn")}</SubmitButton>
    </form>
  );
}

export function StaffCodeForms({ next }: { next: string }) {
  const t = useTranslations();
  const [sent, send] = useActionState(sendStaffCode, undefined);
  const [checked, check] = useActionState(verifyStaffCode, undefined);
  return (
    <div className="flex flex-col gap-4">
      <Messages state={checked?.error ? checked : sent} />
      <form action={send}>
        <SubmitButton variant="secondary" block pendingLabel={t("auth.creator.sending")}>
          {sent?.notice ? t("auth.verify.resend") : t("auth.verify.send")}
        </SubmitButton>
      </form>
      <form action={check} className="flex flex-col gap-4">
        <input type="hidden" name="next" value={next} />
        <Field id="code" label={t("auth.fields.code")}>
          <Input id="code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required className="text-center text-xl tracking-[0.4em]" />
        </Field>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" name="trust" className="size-4 accent-[var(--primary)]" />
          {t("auth.verify.trust")}
        </label>
        <SubmitButton block pendingLabel={t("auth.checking")}>{t("auth.continue")}</SubmitButton>
      </form>
    </div>
  );
}

export function PasswordLinkForm() {
  const t = useTranslations();
  const [state, action] = useActionState(requestPasswordLink, undefined);
  return (
    <form action={action} className="flex flex-col gap-4">
      <Messages state={state} />
      <Field id="email" label={t("auth.fields.workEmail")}>
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </Field>
      <SubmitButton block pendingLabel={t("auth.creator.sending")}>{t("auth.password.sendLink")}</SubmitButton>
    </form>
  );
}

export function NewPasswordForm({ min }: { min: number }) {
  const t = useTranslations();
  const [state, action] = useActionState(setNewPassword, undefined);
  return (
    <form action={action} className="flex flex-col gap-4">
      <Messages state={state} />
      <Field id="password" label={t("auth.password.new")} hint={t("auth.password.rule", { min })}>
        <Input id="password" name="password" type="password" autoComplete="new-password" minLength={min} required aria-describedby="password-hint" />
      </Field>
      <Field id="confirm" label={t("auth.password.confirm")}>
        <Input id="confirm" name="confirm" type="password" autoComplete="new-password" minLength={min} required />
      </Field>
      <SubmitButton block pendingLabel={t("auth.saving")}>{t("auth.password.save")}</SubmitButton>
    </form>
  );
}
