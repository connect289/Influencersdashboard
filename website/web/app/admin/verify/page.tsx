import { redirect } from "next/navigation";
import { Suspense } from "react";
import { Logo } from "@/components/brand/Logo";
import { getAdminSession } from "@/lib/server/admin";
import { VerifyForm } from "./VerifyForm";

export const metadata = { title: "Verify" };

async function Gate() {
  const s = await getAdminSession();
  if (!s) redirect("/admin/login");
  if (s.mfa) redirect("/admin");
  return <VerifyForm email={s.email} />;
}

export default function AdminVerify() {
  return (
    <main id="main" className="grid min-h-dvh place-items-center px-4">
      <div className="glass hairline-lumen grid w-full max-w-sm gap-6 rounded-[var(--radius-xl)] p-6">
        <Logo height={30} />
        <h1 className="text-xl font-semibold">Confirm it&apos;s you</h1>
        <Suspense fallback={<div className="skeleton h-40" />}>
          <Gate />
        </Suspense>
      </div>
    </main>
  );
}
