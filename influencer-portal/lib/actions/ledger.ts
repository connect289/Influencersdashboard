"use server";
// Ledger actions for staff: adjustments and holds (Finance), Eduwit commission receipts, milestone releases and
// recorded breaches (deal owners), and running a deal's ledger now. Each validates its input and calls one inf.*
// function, which decides who may act.
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { requireStaff } from "@/lib/auth/guards";
import { rupeesToPaise } from "@/lib/creators/schemas";
import { act, ledgerDbFail, refreshFinance as refresh } from "@/lib/ledger/act";
import { runDeal } from "@/lib/ledger/runner";
import {
  adjustmentInput,
  holdCreatorInput,
  holdInput,
  manualEventInput,
  receiptInput,
  type AdjustmentInput,
  type ManualEventInput,
  type ReceiptInput,
} from "@/lib/ledger/schemas";
import { log } from "@/lib/log";
import { fail, type ActionResult } from "./result";

export async function postAdjustment(input: AdjustmentInput): Promise<ActionResult> {
  return act(adjustmentInput, input, async (db, v, t) => {
    const { error } = await db.rpc("ledger_adjust", {
      p: {
        creator_id: v.creatorId,
        deal_id: v.dealId ?? "",
        direction: v.direction,
        amount_paise: rupeesToPaise(v.amountRupees),
        tds_component: v.component,
        due_on: v.dueOn ?? "",
        reason: v.reason,
      },
    });
    if (error) return ledgerDbFail(error, t);
    refresh();
    return { ok: true, message: t("finance.ledger.adjusted") };
  });
}

export async function holdEntry(input: z.input<typeof holdInput>): Promise<ActionResult> {
  return act(holdInput, input, async (db, v, t) => {
    const { error } = await db.rpc("ledger_hold", { p_entry: v.entryId, p_hold: v.hold, p_reason: v.reason });
    if (error) return ledgerDbFail(error, t);
    refresh();
    return { ok: true, message: t(v.hold ? "finance.ledger.held" : "finance.ledger.released") };
  });
}

export async function holdCreator(input: z.input<typeof holdCreatorInput>): Promise<ActionResult> {
  return act(holdCreatorInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("ledger_hold_creator", {
      p_creator: v.creatorId,
      p_hold: v.hold,
      p_reason: v.reason,
    });
    if (error) return ledgerDbFail(error, t);
    refresh();
    return {
      ok: true,
      message: t(v.hold ? "finance.ledger.heldCreator" : "finance.ledger.releasedCreator", { count: data }),
    };
  });
}

export async function recordReceipt(input: ReceiptInput): Promise<ActionResult> {
  return act(receiptInput, input, async (db, v, t) => {
    const { error } = await db.rpc("receipt_record", {
      p: {
        enrollment_ref: v.enrollmentRef,
        student_lead_id: v.studentLeadId ?? "",
        status: v.status,
        gross_paise: rupeesToPaise(v.grossRupees),
        received_paise: rupeesToPaise(v.receivedRupees),
        received_on: v.receivedOn ?? "",
        reason: v.reason,
      },
    });
    if (error) return ledgerDbFail(error, t);
    refresh();
    return { ok: true, message: t("finance.receipts.recorded") };
  });
}

export async function recordManualEvent(input: ManualEventInput): Promise<ActionResult> {
  return act(manualEventInput, input, async (db, v, t) => {
    const { error } = await db.rpc("deal_manual_event", {
      p_deal: v.dealId,
      p_kind: v.kind,
      p_ref: v.ref ?? "",
      p_reason: v.reason,
    });
    if (error) return ledgerDbFail(error, t);
    refresh();
    return {
      ok: true,
      message: t(v.kind === "manual_release" ? "finance.deal.released" : "finance.deal.breachRecorded"),
    };
  });
}

/** Runs a deal's ledger now instead of waiting for the next run (deal owners and Finance). */
export async function runDealNow(dealId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.uuid().safeParse(dealId).success) return fail(t("errors.invalidInput"));
  const { me } = await requireStaff("ledger.read");
  if (!me.permissions.has("deal.write") && !me.permissions.has("ledger.adjust")) return fail(t("errors.forbidden"));
  try {
    const r = await runDeal(dealId);
    refresh();
    return {
      ok: true,
      message: r
        ? t("finance.deal.ran", { created: r.created, confirmed: r.confirmed, reversed: r.reversed + r.other })
        : t("finance.deal.noTerms"),
    };
  } catch (e) {
    log.error("ledger.run_failed", { deal_id: dealId, error: e instanceof Error ? e.message : String(e) });
    return fail(t("errors.generic"));
  }
}
