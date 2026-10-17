"use client";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { requestAgencyLink } from "@/lib/actions/agency";

/** Ask a creator (by handle) to link to this agency. The creator then chooses what to grant. */
export function LinkRequest({ agencyId }: { agencyId: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [handle, setHandle] = useState("");
  return (
    <form
      className="flex flex-col gap-2 md:flex-row md:items-end"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () => requestAgencyLink(agencyId, handle),
          () => setHandle(""),
        );
      }}
    >
      <Field
        id="link-handle"
        label={t("agencies.links.handle")}
        hint={t("agencies.links.handleHint")}
        className="flex-1"
      >
        <Input id="link-handle" value={handle} onChange={(e) => setHandle(e.target.value)} maxLength={41} required />
      </Field>
      <Button type="submit" variant="secondary" disabled={pending || handle.trim().length < 2}>
        {t("agencies.links.request")}
      </Button>
    </form>
  );
}
