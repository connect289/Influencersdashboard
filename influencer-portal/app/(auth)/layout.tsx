import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";

export default async function AuthLayout({ children }: { children: React.ReactNode }) {
  const t = await getTranslations();
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex justify-center">
          <Logo label={t("app.tagline")} />
        </div>
        <div className="rounded-2xl bg-surface p-6 shadow-[var(--shadow-card)]">{children}</div>
        <p className="mt-6 text-center text-xs text-muted">{t("app.footer")}</p>
      </div>
    </main>
  );
}
