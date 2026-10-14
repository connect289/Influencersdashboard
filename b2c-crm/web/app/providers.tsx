"use client";
import { ThemeProvider, useTheme } from "next-themes";
import { Toaster } from "sonner";

function ThemedToaster() {
  const { resolvedTheme } = useTheme();
  return <Toaster theme={resolvedTheme === "dark" ? "dark" : "light"} position="bottom-center" closeButton />;
}

/** Light by default; dark only when the person chooses it or their device asks for it (palette.md: no black in light mode). */
export function Providers({ nonce, children }: { nonce?: string; children: React.ReactNode }) {
  return (
    <ThemeProvider attribute="data-theme" defaultTheme="system" enableSystem disableTransitionOnChange nonce={nonce}>
      {children}
      <ThemedToaster />
    </ThemeProvider>
  );
}
