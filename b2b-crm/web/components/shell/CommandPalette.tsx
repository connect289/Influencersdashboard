"use client";
import { useRouter } from "next/navigation";
import { Command } from "cmdk";
import { useTheme } from "next-themes";
import { LogOut, Monitor, Moon, Search, Sun } from "lucide-react";
import { Kbd } from "@/components/ui/Card";
import { NAV } from "@/lib/nav";

const itemCls =
  "flex h-10 cursor-pointer items-center gap-3 rounded-lg px-3 text-[13px] text-fg data-[selected=true]:bg-surface-hover aria-disabled:opacity-50";

export function CommandPalette({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const router = useRouter();
  const { setTheme } = useTheme();
  const run = (fn: () => void) => {
    onOpenChange(false);
    fn();
  };

  return (
    <Command.Dialog
      open={open}
      onOpenChange={onOpenChange}
      label="Command palette"
      overlayClassName="fixed inset-0 z-50 bg-overlay backdrop-blur-sm"
      contentClassName="fixed left-1/2 top-[12vh] z-50 w-[min(640px,calc(100vw-2rem))] -translate-x-1/2 overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl shadow-black/20 animate-fade-in"
    >
      <div className="flex items-center gap-2.5 border-b border-border px-4">
        <Search className="size-4 text-subtle" aria-hidden />
        <Command.Input placeholder="Jump to a screen or run a command…" className="h-12 flex-1 bg-transparent text-sm text-fg outline-none placeholder:text-subtle" />
        <Kbd>Esc</Kbd>
      </div>
      <Command.List className="max-h-[min(420px,60vh)] overflow-y-auto overscroll-contain p-2">
        <Command.Empty className="px-3 py-8 text-center text-[13px] text-muted">No matches.</Command.Empty>
        {NAV.map((group) => (
          <Command.Group key={group.label} heading={group.label} className="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:pb-1 [&_[cmdk-group-heading]]:pt-2 [&_[cmdk-group-heading]]:text-[10.5px] [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:uppercase [&_[cmdk-group-heading]]:tracking-[0.12em] [&_[cmdk-group-heading]]:text-subtle">
            {group.items.map((item) => (
              <Command.Item key={item.href} value={`${item.label} ${item.keywords ?? ""}`} onSelect={() => run(() => router.push(item.href))} className={itemCls}>
                <item.icon className="size-4 text-muted" />
                <span className="flex-1">{item.label}</span>
                {item.key && <span className="flex gap-1"><Kbd>G</Kbd><Kbd>{item.key.toUpperCase()}</Kbd></span>}
              </Command.Item>
            ))}
          </Command.Group>
        ))}
        <Command.Group heading="Preferences" className="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:pb-1 [&_[cmdk-group-heading]]:pt-2 [&_[cmdk-group-heading]]:text-[10.5px] [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:uppercase [&_[cmdk-group-heading]]:tracking-[0.12em] [&_[cmdk-group-heading]]:text-subtle">
          <Command.Item value="theme light" onSelect={() => run(() => setTheme("light"))} className={itemCls}><Sun className="size-4 text-muted" /> Light theme</Command.Item>
          <Command.Item value="theme dark" onSelect={() => run(() => setTheme("dark"))} className={itemCls}><Moon className="size-4 text-muted" /> Dark theme</Command.Item>
          <Command.Item value="theme system" onSelect={() => run(() => setTheme("system"))} className={itemCls}><Monitor className="size-4 text-muted" /> Match system theme</Command.Item>
          <Command.Item value="sign out log out" onSelect={() => run(() => (document.getElementById("signout-form") as HTMLFormElement | null)?.requestSubmit())} className={itemCls}>
            <LogOut className="size-4 text-danger" /> Sign out
          </Command.Item>
        </Command.Group>
      </Command.List>
      <div className="flex items-center gap-4 border-t border-border px-4 py-2.5 text-[11px] text-subtle">
        <span className="flex items-center gap-1"><Kbd>↑</Kbd><Kbd>↓</Kbd> move</span>
        <span className="flex items-center gap-1"><Kbd>↵</Kbd> open</span>
        <span className="ml-auto flex items-center gap-1"><Kbd>G</Kbd> then a letter jumps from anywhere</span>
      </div>
    </Command.Dialog>
  );
}
