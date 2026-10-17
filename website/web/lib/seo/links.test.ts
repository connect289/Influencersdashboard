import { describe, expect, it } from "vitest";
import { suggestLinks } from "./links";

describe("internal linking engine", () => {
  const targets = [
    { path: "/programmes/online-mba", terms: ["online MBA", "MBA"] },
    { path: "/universities/nmims", terms: ["NMIMS"] },
    { path: "/programmes/online-bca", terms: ["BCA"] },
  ];
  it("suggests links for mentions, most specific term first, skipping existing links", () => {
    const s = suggestLinks([{ slug: "choose", text: "Thinking about an online MBA? NMIMS and others offer it. MBAs vary.", links: ["/universities/nmims"] }], targets);
    expect(s).toEqual([{ from_slug: "choose", to_path: "/programmes/online-mba", anchor: "online MBA", reason: "mentions “online MBA”" }]);
  });
  it("matches whole words only and caps suggestions", () => {
    expect(suggestLinks([{ slug: "x", text: "The BCAs and xBCA do not count", links: [] }], targets)).toEqual([]);
    expect(suggestLinks([{ slug: "x", text: "online MBA, NMIMS, BCA", links: [] }], targets, 2)).toHaveLength(2);
  });
});
