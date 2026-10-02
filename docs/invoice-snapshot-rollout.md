# Prospective invoice snapshot safety (draft rollout)

## Scope and evidence

This change applies to newly issued ticket invoices/credit notes, snapshot version 2. It does not change `Gst.breakdown`, ticket prices, seller/entity settings, historical invoice numbers, existing PDFs, or historical tax facts. It is not a generalized finance ledger or a legal compliance certification.

The official CBIC Rule 46 active text specifies the serial limit, recipient particulars, tax rates and reverse-charge indication:
https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule46_v1.00.html
Rule 53 covers credit/debit-note particulars:
https://taxinformation.cbic.gov.in/content/html/tax_repository/gst/rules/cgst_rules/active/chapter6/rule53_v1.00.html

Reviewed 2026-10-02. The requested CBIC explorer URL and direct pages returned HTTP 502 through the research tool; official indexed text confirmed the sixteen-character limit, tax-rate and reverse-charge clauses. Recheck the operative text with finance before activation; signature/e-invoicing/IRN/QR, applicability exceptions and place-of-supply policy are not determined here. Existing example `DQOR/2026-27/0001` has 17 characters; `DQOR-CN/2026-27/0001` has 20. **Do not renumber them.**

## Blockers before deployment

New accounting-document issuance deliberately fails closed; payment/refund processing does not. `Order#mark_paid!` captures document-blocking errors and retains paid status, valid tickets, single coupon consumption, the captured purchase lines, and an explicit `invoice_pending_reason`. Existing pending-confirmation delivery and bounded background retries handle document remediation without claiming an invoice is attached. Legitimate refunds use the original invoice lines or the captured purchase lines, retain processed status/canceled tickets, and expose `credit_note_pending?` plus `order.metadata["credit_notes_pending"]`. `ProcessRefundJob` retries document generation separately after the refund transaction commits, without repeating the gateway refund. No production configuration was changed.

**Do not deploy this draft until seller policy, buyer collection, finance review and an operational pending-document queue are ready.** Production retains its existing code/flows until that readiness decision; this PR does not toggle a live feature or deploy anything. Checkout is not modified here.

Finance must explicitly approve and configure all of:

- `INVOICE_POLICY_VERSION=domestic-18-v1`: acknowledgment of the existing 18% inclusive domestic calculation and existing Maharashtra/interstate routing. This does not change the calculator or establish tax applicability.
- `INVOICE_REVERSE_CHARGE=false`. Other modes are unsupported and blocked, not silently approximated.
- `SELLER_NAME`, `SELLER_ADDRESS`, `SELLER_GSTIN`, `SELLER_SAC`: no defaults. Current calculator supports only a Maharashtra seller; GSTIN format/state and six-digit SAC are checked, not verified against a tax registry.
- `INVOICE_SERIES`, `CREDIT_NOTE_SERIES`: distinct, finance-approved, unused 1–4 uppercase alphanumeric identifiers. There are deliberately no production examples or defaults to copy. Audit existing numbers for prefix collisions before assigning either.
- Verified `order.metadata["billing_address"]`, `["billing_state_name"]`, and `order.billing_state_code` for registered buyers or invoices totaling at least INR 50,000. Optional `metadata["delivery_address"]` is captured/rendered. This patch does not add checkout fields or guess buyer facts. Finance must determine when lower-value unregistered buyers request recipient details and ensure they are collected too.

New numbers use approved-series/YYZZ/NNNNNN; the maximum is 16 characters. Sequences reset in April, remain independently configured for credits, use the existing unique index/retry protection, and stop at 999999. Do not edit an active series casually: configure a new series only with finance approval and an audit of existing numbers. The compact year is intended for contemporary operation, not century-spanning uniqueness.

## Migration and historical documents

Migration `20261002160000` adds three nullable fields to invoices, with no defaults and no data update: `snapshot_version`, `seller_snapshot`, `tax_snapshot`. The backend coordinator identified its check-in migration as 20261002150000; invoice uses 20261002160000 to avoid that collision. Resolve only the additive schema entries if the parallel check-in migration changes the schema version.

1. Before a future authorized rollout, back up the database and attached invoice PDFs; record counts and hashes of issued numbers/snapshots and attachment identifiers.
2. Apply the additive migration first. Existing rows retain NULL snapshot fields. Check historical counts/hashes are unchanged.
3. Deploy only after the blockers above are resolved. Exercise synthetic invoice, PDF, retry, and refund paths in staging with approved nonproduction policy data.
4. Compare archived historical PDFs byte-for-byte and verify a repeated issuance request returns the same historical row/number.
5. Monitor `invoice_pending_reason`, `credit_notes_pending`, refund `credit_note_pending?` and exhausted document jobs. The existing job policy retries five times; finance must remediate remaining cases and re-enqueue `GenerateOrderDocumentsJob` or `ProcessRefundJob` with the original processed event after approval. Never drop validations, overwrite captured purchase amounts, re-request a gateway refund, or invent buyer addresses. Repeated successful document generation returns the same invoice/credit note; existing mail enqueue behavior is unchanged and does not promise exactly-once email delivery.

An already attached historical PDF is returned unchanged. An issued legacy row without its PDF cannot be faithfully reconstructed because the original seller facts were never stored: generation now raises `LegacySnapshotUnavailable`. Finance must locate the original archived artifact. Automatic credit-document generation against legacy rows is deferred rather than inventing seller/tax facts; legitimate gateway refunds and ticket cancellation still complete. Arrange a separately approved historical-credit document process and monitor the pending queue. No automated backfill or historical reissue is included.

For version 2, rendering reads document snapshots only. Credit notes copy original seller, buyer, tax and selected unchanged line snapshots. References must point to an invoice belonging to the same order. Updates through normal model setters, save, update_columns, destroy and delete are blocked; Active Storage attachment/touch operations continue to work. **Bulk SQL/update_all/delete_all and direct attachment replacement remain privileged bypasses.** Database-level append-only enforcement and archival retention controls are separate work; this patch does not claim protection against database administrators.

Do not roll back to old issuing code after version-2 activation: it uses the old numbering and live seller renderer. Stop issuance/workers and fix forward while retaining the columns and documents. Removing the new columns after issuing version-2 documents destroys evidence; the migration refuses rollback once any versioned snapshot exists. A pre-activation schema rollback is safe only after confirming there are zero version-2 documents.

## Validation

Pending-document regressions prove missing configuration/address data preserves paid status, active tickets and single coupon consumption; pending confirmations contain no attachment; original purchase amounts survive later ticket edits; legacy refunds complete with document remediation pending; and retry after policy correction creates only one credit. Targeted tests also cover financial-year numbering, the six-digit boundary/exhaustion, policy rejection, address requirements, exact credit provenance, snapshot-only rendering, immutability, attachment compatibility, legacy PDF preservation, and unchanged invoice/refund monetary reconciliation. All local data is synthetic in `dqor_invoice_task9_test`; no real document was issued or production operation performed.
