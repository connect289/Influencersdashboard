"use client";
import Link from "next/link";
import { LogOut, UserCog } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";

export function UserMenu({ name, subtitle, accountHref, signOutTo, labels }: { name: string; subtitle: string; accountHref: string; signOutTo: string; labels: { menu: string; account: string; signOut: string } }) {
  const initials = name.split(/\s+/).map((p) => p[0] ?? "").join("").slice(0, 2).toUpperCase();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="flex size-10 items-center justify-center rounded-full bg-primary text-sm font-semibold text-on-primary" aria-label={labels.menu}>
        {initials || "?"}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>
          <span className="block text-sm font-medium text-ink">{name}</span>
          <span className="block">{subtitle}</span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild>
          <Link href={accountHref}>
            <UserCog aria-hidden /> {labels.account}
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <form action="/auth/signout" method="post" className="w-full">
            <input type="hidden" name="to" value={signOutTo} />
            <button type="submit" className="flex w-full items-center gap-2">
              <LogOut aria-hidden className="size-4" /> {labels.signOut}
            </button>
          </form>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
