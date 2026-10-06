import { LogoMark } from "@/components/brand/Logo";

/** Split layout: brand panel (desktop) and the form. */
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-[minmax(0,1fr)_minmax(0,560px)]">
      <aside className="relative hidden overflow-hidden bg-navy text-white lg:flex lg:flex-col lg:justify-between lg:p-12">
        <div aria-hidden className="pointer-events-none absolute inset-0 opacity-[0.35] [background:radial-gradient(900px_500px_at_85%_-10%,#f5a800_0%,transparent_55%),radial-gradient(700px_500px_at_-10%_110%,#1f5aa6_0%,transparent_60%)]" />
        <div aria-hidden className="pointer-events-none absolute inset-0 opacity-[0.07] [background-image:linear-gradient(#fff_1px,transparent_1px),linear-gradient(90deg,#fff_1px,transparent_1px)] [background-size:40px_40px]" />
        <div className="relative flex items-center gap-3">
          <LogoMark size={40} />
          <span className="text-lg font-semibold tracking-tight">Edu<span className="text-amber">wit</span></span>
        </div>
        <div className="relative max-w-lg">
          <p className="text-[13px] font-medium uppercase tracking-[0.16em] text-amber">Partner CRM</p>
          <h1 className="mt-3 text-4xl font-semibold leading-tight tracking-tight">Every lead to the partner that earns the most.</h1>
          <p className="mt-4 text-[15px] leading-7 text-white/70">
            Allocation, live partner sync, student notifications and commission, explained from stored records.
          </p>
        </div>
        <p className="relative text-xs text-white/50">Restricted to Eduwit's administrator. Every sign-in is logged.</p>
      </aside>
      <main className="flex items-center justify-center px-5 py-12 sm:px-10">
        <div className="w-full max-w-[380px] animate-fade-in">{children}</div>
      </main>
    </div>
  );
}
