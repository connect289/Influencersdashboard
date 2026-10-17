import { serialiseLd } from "@/lib/seo/jsonld";

/** Inline JSON-LD (data, not executed). Escaped by serialiseLd. */
export function JsonLd({ data }: { data: Record<string, unknown> | Record<string, unknown>[] }) {
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: serialiseLd(data) }} />;
}
