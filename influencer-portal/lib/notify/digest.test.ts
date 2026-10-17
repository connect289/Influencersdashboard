import { describe, expect, it } from "vitest";
import { creatorDigest, staffDigest } from "./digest";

const quiet = {
  name: "Riya",
  new_leads: 0,
  enrolled: 0,
  earned_paise: 0,
  payable_paise: 0,
  due_soon: 0,
  overdue: 0,
  unread_messages: 0,
};

describe("digests", () => {
  it("sends nothing when nothing happened", () => {
    expect(creatorDigest(quiet, "daily")).toBeNull();
    expect(
      staffDigest({
        overdue_deliverables: 0,
        pending_reviews: 0,
        pending_negotiations: 0,
        contracts_expiring: 0,
        payouts_due_paise: 0,
        kyc_pending: 0,
        fraud_flags: 0,
        unread_messages: 0,
      }),
    ).toBeNull();
  });

  it("summarises a creator's leads, earnings and due work", () => {
    const d = creatorDigest(
      { ...quiet, new_leads: 3, enrolled: 1, earned_paise: 2_500_00, overdue: 1, due_soon: 2 },
      "weekly",
    );
    expect(d?.title).toBe("Your week on Eduwit");
    expect(d?.lines).toEqual([
      "3 new leads last week.",
      "1 student enrolled last week.",
      "You earned ₹2,500.00 last week.",
      "1 deliverable is overdue.",
      "2 deliverables are due this week.",
    ]);
  });

  it("summarises the staff queues", () => {
    expect(
      staffDigest({
        overdue_deliverables: 2,
        pending_reviews: 1,
        pending_negotiations: 0,
        contracts_expiring: 0,
        payouts_due_paise: 10_000_00,
        kyc_pending: 0,
        fraud_flags: 1,
        unread_messages: 0,
      })?.lines,
    ).toEqual([
      "1 concept or draft waiting for review.",
      "2 deliverables overdue.",
      "₹10,000.00 of payouts due.",
      "1 open fraud flag.",
    ]);
  });
});
