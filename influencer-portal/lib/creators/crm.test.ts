import { describe, expect, it } from "vitest";
import {
  activeFilterCount,
  creatorFiltersToQuery,
  creatorInput,
  filtersForView,
  filtersToRpc,
  istToIso,
  mapHeaders,
  parseCreatorFilters,
  prepareImport,
} from "./crm";

describe("creator filters in the URL", () => {
  it("parses valid values and drops invalid ones without failing", () => {
    const f = parseCreatorFilters({
      q: " riya ",
      stage: "prospect,contacted,bogus",
      platform: "tiktok",
      followers_min: "10000",
      followers_max: "abc",
      owner_id: "me",
      page: "2",
      page_size: "37",
      include_blocked: "1",
    });
    expect(f.q).toBe("riya");
    expect(f.stage).toEqual([]);
    expect(f.platform).toBeUndefined();
    expect(f.followers_min).toBe(10000);
    expect(f.followers_max).toBeUndefined();
    expect(f.owner_id).toBe("me");
    expect(f.page).toBe(2);
    expect(f.page_size).toBeUndefined();
    expect(f.include_blocked).toBe(true);
  });
  it("accepts a clean multi-value stage list", () => {
    expect(parseCreatorFilters({ stage: "prospect,contacted" }).stage).toEqual(["prospect", "contacted"]);
    expect(parseCreatorFilters({ stage: ["active", "paused"] }).stage).toEqual(["active", "paused"]);
  });
  it("round-trips through a query string", () => {
    const f = parseCreatorFilters({
      stage: "active,paused",
      niche: "mba",
      followers_min: "5000",
      sort: "name",
    });
    const q = creatorFiltersToQuery(f);
    expect(q).toBe("followers_min=5000&niche=mba&sort=name&stage=active%2Cpaused");
    expect(parseCreatorFilters(Object.fromEntries(new URLSearchParams(q)))).toEqual(f);
  });
  it("counts active filters (not search, sort or paging) and builds RPC and saved-view payloads", () => {
    const f = parseCreatorFilters({
      q: "x",
      stage: "active",
      niche: "mba",
      sort: "name",
      page: "3",
    });
    expect(activeFilterCount(f)).toBe(2);
    expect(filtersForView(f)).toEqual({ q: "x", stage: ["active"], niche: "mba", sort: "name" });
    expect(filtersToRpc(parseCreatorFilters({}))).toMatchObject({
      page: 1,
      page_size: 25,
      sort: "updated",
      dir: "desc",
    });
  });
});

describe("creatorInput", () => {
  it("normalises handles and validates phone", () => {
    expect(creatorInput.parse({ displayName: "Riya", handle: "@Riya.Learns" }).handle).toBe("riya.learns");
    expect(creatorInput.safeParse({ displayName: "Riya", handle: "ri" }).success).toBe(false);
    expect(creatorInput.safeParse({ displayName: "Riya", handle: "riya", phone: "123" }).success).toBe(false);
  });
});

describe("istToIso", () => {
  it("converts IST wall time to UTC", () => {
    expect(istToIso("2026-10-20", "10:30")).toBe("2026-10-20T05:00:00.000Z");
    expect(istToIso("2026-10-20")).toBe("2026-10-20T04:30:00.000Z");
    expect(istToIso("20-10-2026")).toBe("");
  });
});

describe("CSV import preparation", () => {
  it("maps header aliases and reports missing required columns", () => {
    expect(mapHeaders(["Full Name", "Username", "E-mail", "Mobile", "Profile URL", "x"]).map).toEqual([
      "display_name",
      "handle",
      "email",
      "phone",
      "platform_url",
      null,
    ]);
    expect(mapHeaders(["Name", "Email"]).missing).toEqual(["handle"]);
  });
  it("validates rows, normalises values and reports errors with file line numbers", () => {
    const { valid, invalid } = prepareImport(
      ["name", "handle", "email", "phone", "platform", "url", "followers", "niches"],
      [
        [
          "Riya",
          "@Riya.Learns",
          "RIYA@x.in",
          "98765 43210",
          "Instagram",
          "https://instagram.com/riya",
          "1,20,000",
          "MBA; Finance",
        ],
        ["", "bad handle!", "nope", "12", "tiktok", "", "lots", ""],
        ["Arjun", "arjun_mba", "", "", "youtube", "", "", ""],
      ],
    );
    expect(valid).toHaveLength(1);
    expect(valid[0]).toMatchObject({
      row: 2,
      handle: "riya.learns",
      email: "riya@x.in",
      phone: "+919876543210",
      platform: "instagram",
      followers: "120000",
      niches: ["MBA", "Finance"],
    });
    expect(invalid.map((r) => r.row)).toEqual([3, 4]);
    expect(invalid[0]?.reason.split(",").sort()).toEqual(
      ["email", "followers", "handle", "name", "phone", "platform", "platform_pair"].sort(),
    );
    expect(invalid[1]?.reason).toBe("platform_pair");
  });
});
