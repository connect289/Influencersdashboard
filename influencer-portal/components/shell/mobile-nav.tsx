"use client";
import { Menu } from "lucide-react";
import { useState } from "react";
import { Dialog as D } from "radix-ui";
import { Button } from "@/components/ui/button";
import { SideNav, type NavLink } from "./nav-links";

export function MobileNav({ links, labels }: { links: NavLink[]; labels: { open: string; title: string } }) {
  const [open, setOpen] = useState(false);
  return (
    <D.Root open={open} onOpenChange={setOpen}>
      <D.Trigger asChild>
        <Button variant="ghost" size="icon" aria-label={labels.open} className="md:hidden">
          <Menu />
        </Button>
      </D.Trigger>
      <D.Portal>
        <D.Overlay className="fixed inset-0 z-40 bg-black/40" />
        <D.Content className="fixed inset-y-0 left-0 z-50 w-72 bg-surface p-4 shadow-[var(--shadow-card)]">
          <D.Title className="mb-4 text-base font-semibold">{labels.title}</D.Title>
          <D.Description className="sr-only">{labels.title}</D.Description>
          <nav aria-label={labels.title}>
            <SideNav links={links} onNavigate={() => setOpen(false)} />
          </nav>
        </D.Content>
      </D.Portal>
    </D.Root>
  );
}
