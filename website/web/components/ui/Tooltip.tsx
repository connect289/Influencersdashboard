"use client";

import { Tooltip as T } from "radix-ui";

/** Short explanation on hover/focus (e.g. "What UGC-DEB entitlement means"). Content must also be reachable without
 * hover on touch devices — use it only to add, never to hide, essential information. */
export function Tooltip({ content, children }: { content: React.ReactNode; children: React.ReactNode }) {
  return (
    <T.Provider delayDuration={250}>
      <T.Root>
        <T.Trigger asChild>{children}</T.Trigger>
        <T.Portal>
          <T.Content
            sideOffset={8}
            className="glass-strong text-text z-[var(--z-toast)] max-w-xs rounded-[var(--radius-md)] px-3 py-2 text-sm"
          >
            {content}
            <T.Arrow className="fill-[var(--surface-solid)]" />
          </T.Content>
        </T.Portal>
      </T.Root>
    </T.Provider>
  );
}
