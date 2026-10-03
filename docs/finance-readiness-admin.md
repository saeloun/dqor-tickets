# Finance readiness administration (stacked draft)

This follow-up depends on PR #148 (`codex/invoice-snapshot-safety`) and leaves its green commit intact. It supplies checkout billing capture, a private administrator remediation queue, buyer follow-up links, and staged seller-policy review records. It does not activate issuance, change runtime environment values, change rates, issue real documents, rewrite historical snapshots, send buyer messages, or operate production. It is current single-event commerce administration using the existing `AdminUser.admin` role, not organization tenancy or a global-admin bypass into the separate Organization/Event foundation.

## Buyer details with minimal checkout friction

Personal orders below INR 50,000 need no extra billing fields. Registered buyers, orders at or above INR 50,000 after discounts, and buyers requesting invoice billing details must provide billing address, state name and two-digit GST state code. Registered buyers also provide their registered legal name. The supplied state must match the GSTIN prefix; code/name correctness is subject to buyer/finance verification, not registry lookup. Delivery address is optional when different.

Client-side requirements track quantity, GSTIN and coupon previews; server validation is authoritative and runs before order/ticket creation or gateway calls. Only allowlisted billing metadata is accepted. Buyer data is not added to attendee pages or exports. Billing fields and policy data are filtered from parameter logs. Order metadata, invoice buyer/seller snapshots and policy-review data are also marked sensitive for Active Record filtering.

## Administrator workflow

The Avo navigation links to `/finance/documents`. Existing authenticated administrators can access it; desk staff and attendee sessions cannot. The queue displays recorded invoice/document blockers and processed refunds with missing credit notes, oldest first, with pagination and exact order-code search. It does not modify payment or refund status.

For an unissued order, an admin may save facts verified with the buyer, or generate a private follow-up link and share it through their approved channel. Generating a link sends no message. The link expires after seven days, is replaced when a new request is generated, and is consumed on a successful save. Invalid/incomplete submissions do not consume it. Billing pages use no-store/no-referrer/noindex and contain no external scripts.

Updates only accept billing address/state name/delivery address, plus state code or registered name when missing. Existing captured state code and registered name cannot change here; GSTIN, price, status, email, purchase lines and other metadata are never editable through these endpoints. Order-row locking serializes normal issuance and billing edits. Once any invoice exists, billing editing/link use is blocked. Optimistic billing revisions prevent stale saves; the metadata audit records actor, time and field names without duplicating addresses. Approved seller reviews also use optimistic locking and are immutable through normal model writes.

Admins can explicitly queue **document-only** retries when an approved review matches separately configured runtime policy. Credit-note retries require the original processed event, matched to the refund's gateway ID or its free-refund event, not simply an equal amount. The selector only offers matching confirmations. No gateway refund is requested by this workflow. Historical missing seller facts remain a finance-remediation case; the UI does not invent facts, upload replacements, renumber documents, or reconstruct historical PDFs.

## Draft, configured, approved — never activated by this UI

`/finance/policies` starts blank, with no guessed entity or rate values.

| State | Meaning | Allowed next action |
| --- | --- | --- |
| Draft | Facts may be incomplete | Save draft or check/configure |
| Configured | All required facts passed structural/supported-policy checks | Review read-only facts and approve, or reopen as draft |
| Approved | Named administrator confirmed those exact facts at a recorded time | Read or copy to a new draft; never edit in place |

Edits require review again. Stale forms cannot overwrite a newer edit or approve it. Approval is an internal review record, not registry verification or a legal-compliance guarantee. It never writes ENV, picks a live policy, or issues documents. Runtime match is only a read-only comparison and a prerequisite for a separate explicit retry action.

## Exact facts still required from finance before activation

- Seller legal name, complete registered address, GSTIN and verified six-digit SAC.
- Two distinct approved, unused invoice/credit series identifiers, each 1–4 uppercase letters/digits; check existing serials for collisions.
- Explicit reviewed total GST rate and CGST/SGST/IGST components. The current unchanged calculator supports only total 18%, CGST 9%, SGST 9%, IGST 18%; any other rate requires implementation.
- Explicit reverse-charge determination. The current unchanged calculator supports only `false`; unsupported modes are blocked.
- Reviewed place-of-supply policy and its basis. The only implemented identifier is `domestic-18-v1`: the existing Maharashtra-seller domestic/inclusive routing, including its treatment of unregistered buyers. Applicability requires finance review, not an assumption that the code makes it correct.
- Policy basis/review notes and an authorized administrator's explicit approval. Other tax particulars, signature/e-invoice/IRN/QR obligations and exceptions remain part of the finance review documented in PR #148.

A future separately authorized readiness/rollout step must configure the exact approved facts in `SELLER_NAME`, `SELLER_ADDRESS`, `SELLER_GSTIN`, `SELLER_SAC`, `INVOICE_SERIES`, `CREDIT_NOTE_SERIES`, `INVOICE_POLICY_VERSION` and `INVOICE_REVERSE_CHARGE`. This UI deliberately provides no activation button. Do not merge/deploy assuming saved approval enabled invoicing.

## Migration and merge coordination

Migration `20261002190000` creates only `invoice_policy_reviews`, with creator/approver references to existing administrators and optional prior-review lineage. It performs no backfill or access grants. It avoids reserved invoice160000, slots170000, foundation180000, and other backend/branding migrations. Rollback refuses to erase approved review records. Bulk SQL remains a privileged administrative bypass; this is not database-level tamper-proof archival enforcement.

Billing details, revisions, expiring-link nonce and audit field names use existing order metadata. Merge checkout/cart/routes carefully with the coordinated backend task; no check-in/native/foundation files are part of this draft. Run the migrations against a backed-up staging database after PR #148, verify blank review defaults and admin-only access, then exercise synthetic registration/high-value/discounted checkout, missing-data follow-up, stale/expired links, and document-only retries before any separately authorized production rollout.

Local verification uses only synthetic `dqor_finance_task9_test` data. No real seller policy has been approved, no messages sent, and no production documents or configuration changed.

## Refund/admission integration lock order

Refund processing acquires `order -> refund -> ticket` locks before document issuance or pending-document metadata writes. Admission uses `order -> ticket`; slot redemption uses `slot -> order -> ticket`. Keep the shared order lock ahead of ticket/refund mutation when integrating those branches. Refund and credit-note retries retain the same outer order lock.

A two-connection PostgreSQL regression holds the admission order lock, waits until the refund actually blocks, then attempts ticket admission. Before the fix both issued-invoice and pending-invoice cases reproduced `ActiveRecord::Deadlocked`; after the fix admission completes and refund cancellation follows, with document replay remaining idempotent. This is an integration prerequisite for finance, not a reason to include finance in the separate first check-in release.
