import Image from "next/image";
import { type ReactNode } from "react";

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center px-4 py-10">
      <div className="mb-6 flex items-center gap-3">
        <Image src="/brand/eduwit-mark.png" alt="" width={40} height={40} priority />
        <div>
          <p className="text-lg font-semibold">Eduwit One</p>
          <p className="text-sm text-fg-muted">Monitoring, alerts and fixes for Eduwit&apos;s apps</p>
        </div>
      </div>
      <div className="rounded-lg border border-border bg-surface p-5">{children}</div>
    </main>
  );
}
