import { describe, expect, it } from "vitest";
import type { OfferingCard } from "@/lib/search/types";
import { courseLd, serialiseLd } from "./jsonld";

describe("structured data", () => {
  const o = { id: 7, programme_name: "MBA", spec_name: "Marketing", university: { slug: "nmims", name: "NMIMS" }, mode: "Online", fee: { total: 196000 }, duration_months: 24 } as unknown as OfferingCard;
  it("course carries only catalogue facts", () => {
    const ld = courseLd(o, "https://eduwit.in");
    expect(ld).toMatchObject({ name: "MBA in Marketing", offers: { price: 196000, priceCurrency: "INR" }, hasCourseInstance: { courseWorkload: "P2Y" } });
  });
  it("no fee → no offer", () => {
    expect(courseLd({ ...o, fee: {} }, "https://eduwit.in")).not.toHaveProperty("offers");
  });
  it("cannot break out of the script element", () => {
    expect(serialiseLd({ x: "</script><script>alert(1)</script>" })).not.toContain("</script>");
  });
});
