import { describe, expect, it } from "vitest";
import { adDay, adRows } from "./ad-csv";

describe("ad spend CSV", () => {
  it("reads a Meta Ads Manager export by day", () => {
    const csv = "Reporting starts,Reporting ends,Campaign name,Campaign ID,Ad set name,Amount spent (INR),Impressions,Link clicks,Leads\n" +
      "2026-10-13,2026-10-13,MBA Oct,120200,Delhi 25-35,\"1,000.50\",4000,50,6\n2026-10-14,2026-10-14,MBA Oct,120200,Delhi 25-35,500,2000,20,\n,,Total,,,1500.50,,,\n";
    const r = adRows(csv);
    expect(r.guess).toBe("meta");
    expect(r.rows).toHaveLength(2);
    expect(r.skipped).toBe(1);
    expect(r.rows[0]).toEqual({ day: "2026-10-13", campaign_id: "120200", campaign: "MBA Oct", adset: "Delhi 25-35", spend: "1000.50", impressions: "4000", clicks: "50", leads: "6", currency: "INR" });
  });
  it("reads a Google Ads report with title lines above the header", () => {
    const csv = "Campaign report\n\"October 1, 2026 - October 14, 2026\"\nDay,Campaign,Campaign ID,Currency code,Cost,Impr.,Clicks,Conversions\n" +
      "\"Oct 14, 2026\",Search brand,G1,INR,300.00,900,45,3.00\nTotal: Account,,,,300.00,900,45,3.00\n";
    const r = adRows(csv);
    expect(r.guess).toBe("google");
    expect(r.rows).toEqual([{ day: "2026-10-14", campaign_id: "G1", campaign: "Search brand", adset: "", spend: "300.00", impressions: "900", clicks: "45", leads: "3", currency: "INR" }]);
  });
  it("says what is missing and reads the date shapes", () => {
    expect(adRows("a,b\n1,2").missing).toHaveLength(1);
    expect(adDay("14/10/2026")).toBe("2026-10-14");
    expect(adDay("14 Oct 2026")).toBe("2026-10-14");
    expect(adDay("yesterday")).toBeNull();
    expect(adRows("Day,Campaign,Amount spent (USD)\n2026-10-14,X,5").rows[0]?.currency).toBe("USD");
  });
});
