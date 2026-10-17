"use client";
import { ThemeProvider } from "next-themes";
import { Toaster } from "sonner";

export function Providers({ nonce, children }: { nonce?: string; children: React.ReactNode }) {
  return (
    <ThemeProvider attribute="data-theme" defaultTheme="light" enableSystem disableTransitionOnChange nonce={nonce}>
      {children}
      <Toaster position="top-center" richColors closeButton toastOptions={{ duration: 4000 }} />
    </ThemeProvider>
  );
}
