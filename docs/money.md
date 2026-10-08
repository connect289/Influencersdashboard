# Eduwit B2B CRM: commission and finance

The B2B CRM tracks what partners owe Eduwit (receivables). Payouts to Eduwit's own counsellors belong to the B2C CRM.
Everything here is on the **Commission & Finance** screen (`/money`).

## From enrolment to cash

1. **Enrolment reported.** When a partner moves a lead to *enrolled* (webhook, polling, or the partner's statement), the CRM
   records an enrolment within 5 minutes (`b2b-money-tick`) with status *to verify*. It also books an **expected**
   commission line from the rate in force on the enrolment date. You can also record one by hand from the lead's Eduwit
   reference. Test leads never earn commission.
2. **Verification.** You check the proof: a partner statement line, a university confirmation or a fee receipt. Correct the
   fee or the date if the proof differs, then press **Verify**. The commission is recomputed and becomes **realised**,
   net of GST. The lead moves to *verified*.
3. **Month close.** On the 7th of each month (configurable), or when you press *Close month*, last month is closed:
   - **Tiered rates are settled.** The tier comes from the month's verified enrolments ÷ leads the partner accepted that
     month. If the settled tier differs from the provisional one, a tier settlement line (positive or negative) is added.
     Realised lines are never edited.
   - **Draft invoices are built.** Each partner gets one draft invoice with every realised line not yet invoiced: commission,
     tier settlements, refund reversals and adjustments.
4. **Invoice approval.** Open the draft and check it, then press **Approve**:
   - It gets the next number in the financial year (`EDW/2026-27/0001`), with no gaps.
   - It gets today's date and a due date from the partner's payment terms.
   - Both parties' details are frozen on it.
   - Tax is **IGST** when the two states differ, **CGST + SGST** when they match.
   - Leads on the invoice move to *commission booked*.

   The CRM does not email invoices. Use **Print or save PDF**, send the file yourself, then press **Mark as sent**.
5. **Receipts.** Record each payment with the amount that reached the bank, the TDS deducted and the bank reference (UTR).
   - **Matching.** It goes to the open invoice whose outstanding equals amount + TDS. If none matches, it fills the oldest
     open invoices first. You can also choose the invoice yourself.
   - **Leftovers.** A receipt with money left over can be applied later.
   - **Mistakes.** Void a receipt entered by mistake; its invoices reopen.
   - **Paid invoices.** These move their leads to *paid*.
6. **Overdue reminders.** Every day an invoice past its due date raises `alert.invoice_overdue` on the Command Center. It
   alerts on the due date, then again at 30, 60 and 90 days past it. The partner is never messaged.

Ageing on the overview groups outstanding amounts by days since the invoice date: 0–30, 31–60, 61–90 and 90+.

## Refunds and adjustments

- **Refund.** A refund within the refund window (30 days from enrolment by default) reverses the commission with negative
  lines. An invoiced commission is credited on the next invoice. After the window, the refund needs an explicit "Eduwit
  agreed" tick.
- **Adjustment.** Anything else agreed with a partner, such as a goodwill credit or a missed payout, is an **adjustment**: a
  signed net amount with a note, realised at once.
- **Cancel.** A wrong enrolment report that is still unverified is **cancelled** with a reason. The money scan does not
  recreate it.

## Statement reconciliation

Upload the partner's own statement (Excel .xlsx or CSV, up to 5,000 rows) for a period and say which column is which.

**Matching.** Each row is matched in this order:
1. Eduwit reference;
2. the partner's record ID;
3. phone;
4. name plus programme (only when exactly one lead fits).

**The piles.** Matched rows fall into four piles. Each pile exports as CSV to send the partner.

| Pile | Meaning | What you can do |
| --- | --- | --- |
| Matched | Both sides have the enrolment and the amount agrees with Eduwit's commission (net or with GST) | **Verify** (the line is the proof), or *Verify all matched* |
| Amount mismatch | Both sides have it, amounts differ | Verify anyway, record an adjustment, or dismiss with a note |
| Partner only | On the statement, not enrolled in Eduwit's records: possible leakage | **Record enrolment** when the student was sent by Eduwit, else dismiss |
| Eduwit only | Enrolled in Eduwit's records in the period, missing from the statement | Raise it with the partner |

## Commission rates

Commission is set at three levels. Rates are versioned and never edited. The most specific rate in force on the
enrolment date wins:

1. **Programme.** Each partner has its own programme sheet (Excel or Google Sheet, one row per programme) in the
   Programme Repository. It carries the programme details, fees and a **commission %** column.
   - **Publishing confirms it.** Publishing the reviewed sheet turns each commission into a programme-level rate for that
     partner.
   - **GST.** The % is taken as GST-inclusive. Untick *The % includes 18% GST* on the partner's Live programmes tab if
     its sheet states commission before GST; the rates follow at once.
   - **Changes.** A changed % starts a new rate from the publishing day. A programme whose commission is removed from
     the sheet falls back to the university or partner rate from the next day.
   - **Excel.** Cells formatted as a percentage (18%) are read correctly.
   - **Tier references.** A "Tier 2" in the sheet is skipped; set tiered rates by hand.
2. **University.** One rate for every programme of a university at this partner: Routing → Rates → *Level: One
   university*.
3. **Partner.** Everything else the partner offers: Routing → Rates → *Level: Partner-wide*.

Catalogue-wide programme and university rates (without a partner) remain as a last fallback.

A template with the expected columns is linked from the partner's upload screen (`/programme-sheet-template.csv`).

- **Percent** of the first-year fee or the total fee. The fee comes first from the partner's Programme Repository file, then
  from the catalogue. The total-fee base uses the fee recorded on the enrolment first. If the first-year fee is unknown, the
  total is used and the line says so.
- **Fixed** rupees per enrolment.
- **Tiered**: the rate depends on the partner's lead-to-enrolment conversion in the month. Enter tiers as
  `0: 22.42, 7: 20.42, 9: 18.42` (conversion from %: rate %).
  - **During the month** the tier is provisional:
    - projected from the month's enrolments ÷ leads accepted, once the partner has at least 20 accepted leads (setting);
    - before that, the last settled month's tier;
    - with no history, the first tier.
  - **Tier watch** on the overview shows the current tier and how many more enrolments reach the next one.
- **GST.** If a rate *includes* GST, the net is rate ÷ 1.18. Otherwise GST is added on top.

## Settings (Commission & Finance → Settings)

- **Tax.** GST rate, SAC code, usual TDS, and whether Eduwit's CA has confirmed them.
- **Eduwit on the invoice.** Legal name, GSTIN, state code, registered address, bank details, and the invoice prefix.
- **Rules.**
  - The refund window.
  - The minimum leads before a tier is projected.
  - The day last month is closed, and whether that close happens automatically.
- **Partner billing.** For each partner: legal name, GSTIN (or state code), billing address, accounts email and payment
  terms.

An invoice cannot be approved without Eduwit's legal name, GSTIN, address and SAC code, plus the partner's legal name,
address and state.

## Accounting exports

The overview exports CSV for Tally or Zoho Books for any date range:
- the sales register (invoices with taxable value, CGST, SGST, IGST and totals);
- receipts (with TDS and the invoices they were applied to);
- realised earning lines.

## Rules the database enforces

- **Ledger lines.** Earning lines, invoices, invoice lines, receipts and receipt applications are never removed; a trigger
  refuses it.
- **Realised lines.** A realised line's amounts never change. Corrections are new lines: a reversal, a tier settlement or an
  adjustment.
- **One enrolment per allocation.** Each allocation has at most one live enrolment, and each enrolment has one commission
  line.
- **Invoice numbers.** Numbers are sequential per financial year. A cancelled approved invoice keeps its number and shows as
  cancelled; issue the credit note in the accounts.
- **Shared enrolments table.** Enrolments live in the shared `public.enrollments` table with `source_product = 'b2b'`. The
  B2C CRM writes its own rows there. The B2B ledger (`b2b.earnings`, `b2b.invoices`, `b2b.receipts`, statements) holds
  partner money only.
