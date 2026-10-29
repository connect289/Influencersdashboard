"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { archiveChatThread } from "@/lib/actions/chat.ts";

export function ArchiveThreadButton({ id }: { id: number }) {
  return (
    <ActionForm action={archiveChatThread}>
      <input type="hidden" name="id" value={id} />
      <Button type="submit" variant="ghost" size="sm">
        Archive
      </Button>
    </ActionForm>
  );
}
