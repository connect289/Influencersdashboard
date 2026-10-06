"use client";
import { ThemeProvider, useTheme } from "next-themes";
import { Toaster } from "sonner";

function ThemedToaster() {
  const { resolvedTheme } = useTheme();
  return <Toaster theme={resolvedTheme === "dark" ? "dark" : "light"} position="bottom-right" richColors closeButton />;
}

export function Providers({ nonce, children }: { nonce?: string; children: React.ReactNode }) {
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange nonce={nonce}>
      {children}
      <ThemedToaster />
    </ThemeProvider>
  );
}
