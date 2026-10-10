require "rails_helper"

RSpec.describe "Private finance administration", type: :request do
  let(:admin) { create(:admin_user) }
  let(:order) { create(:order, :paid, metadata: { "invoice_pending_reason" => "InvoicePolicy::NotConfigured" }) }
  let(:billing) { { billing_address: "Private buyer street", billing_state_name: "Maharashtra", billing_state_code: "27" } }

  it "requires an authenticated administrator for every finance entrypoint" do
    get finance_documents_path
    expect(response).to redirect_to(new_session_path)
    sign_in_admin(create(:admin_user, role: :desk))
    get finance_documents_path
    expect(response).to have_http_status(:forbidden)
    get finance_policies_path
    expect(response).to have_http_status(:forbidden)
    post finance_policies_path, params: { policy_data: finance_policy_facts }
    expect(response).to have_http_status(:forbidden)
    patch finance_document_path(order), params: { billing:, verified: "1", billing_revision: 0 }
    expect(response).to have_http_status(:forbidden)
    expect(order.reload.metadata).not_to have_key("billing_address")
  end

  it "renders an uncached private queue and excludes billing data from attendee-facing pages" do
    sign_in_admin(admin)
    order.update!(metadata: order.metadata.merge("billing_address" => "Private buyer street"))
    get finance_documents_path
    expect(response.body).to include(order.code)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    get finance_document_path(order)
    expect(response.body).to include("Private buyer street", "Create private buyer follow-up link")
    get tickets_store_path
    expect(response.body).not_to include("Private buyer street")
  end

  it "accepts only verified safe billing edits and rejects stale or issued-record changes" do
    sign_in_admin(admin)
    patch finance_document_path(order), params: { billing:, billing_revision: 0 }
    expect(response).to have_http_status(:unprocessable_content)
    patch finance_document_path(order), params: { billing: billing.merge(gstin: "29AAAAA0000A1Z5", total_paise: 1), verified: "1", billing_revision: 0 }
    expect(response).to have_http_status(:redirect)
    expect(order.reload.total_paise).to eq(350_000)
    expect(order.gstin).to be_nil
    patch finance_document_path(order), params: { billing:, verified: "1", billing_revision: 0 }
    expect(response).to have_http_status(:conflict)
    create(:ticket, order:)
    invoice = Invoice.issue_for!(order)
    patch finance_document_path(order), params: { billing: billing.merge(billing_address: "Replacement"), verified: "1", billing_revision: 1 }
    expect(response).to have_http_status(:conflict)
    expect(invoice.reload.buyer_snapshot["billing_address"]).to eq("Private buyer street")
  end

  it "requires explicit staged review, rejects stale approval and never activates runtime configuration" do
    sign_in_admin(admin)
    original_env = ENV.to_h
    post finance_policies_path, params: { policy_data: finance_policy_facts, status: "approved" }
    review = InvoicePolicyReview.last
    expect(review).to be_draft
    post approve_finance_policy_path(review), params: { review_confirmed: "1", lock_version: review.lock_version }
    expect(response).to have_http_status(:unprocessable_content)
    post configure_finance_policy_path(review), params: { lock_version: review.lock_version }
    expect(review.reload).to be_configured
    get finance_policy_path(review)
    expect(response.body).to include("Configured facts", "Reopen as draft to edit facts")
    expect(response.body).not_to include('name="policy_data[seller_name]"')
    post approve_finance_policy_path(review), params: { review_confirmed: "1", lock_version: review.lock_version - 1 }
    expect(response).to have_http_status(:conflict)
    post approve_finance_policy_path(review), params: { review_confirmed: "1", lock_version: review.lock_version }
    expect(review.reload).to be_approved
    expect(review.approved_by).to eq(admin)
    expect(ENV.to_h).to eq(original_env)
    patch finance_policy_path(review), params: { policy_data: finance_policy_facts, lock_version: review.lock_version }
    expect(response).to have_http_status(:conflict)
    post duplicate_finance_policy_path(review)
    expect(InvoicePolicyReview.last).to be_draft
    expect(InvoicePolicyReview.last.supersedes).to eq(review)
  end

  it "returns a configured review to draft after editing facts" do
    sign_in_admin(admin)
    review = InvoicePolicyReview.create!(created_by: admin, policy_data: finance_policy_facts, status: :configured, configured_at: Time.current)
    patch finance_policy_path(review), params: { policy_data: finance_policy_facts.merge("seller_name" => "Revised test seller"), lock_version: review.lock_version }
    expect(review.reload).to be_draft
    expect(review.configured_at).to be_nil
    expect(review.approved_at).to be_nil
  end

  it "requires matching reviewed configuration and explicit confirmation for document-only retries" do
    sign_in_admin(admin)
    post retry_document_finance_document_path(order), params: { confirmed: "1" }
    expect(response).to have_http_status(:unprocessable_content)
    approved_finance_policy(admin)
    expect { post retry_document_finance_document_path(order), params: { confirmed: "1" } }.to have_enqueued_job(GenerateOrderDocumentsJob).with(order)
    expect(order.reload).to be_paid
    expect(order.invoices).to be_empty
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(InitiateRefundJob)
  end

  it "retains a blocked document in the finance queue and completes only after an explicitly reviewed retry" do
    sign_in_admin(admin)
    ticket = create(:ticket, order:)
    allow(PdfRenderer).to receive(:render).and_return("%PDF-synthetic")
    allow(InvoicePolicy).to receive(:snapshot).and_raise(InvoicePolicy::NotConfigured)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: MailDeliveryJob) { DeliverOrderConfirmationJob.perform_now(order) }
    GenerateOrderDocumentsJob.perform_now(order.reload)
    captured = order.reload.metadata.fetch("invoice_purchase_lines")
    get finance_documents_path
    expect(response.body).to include(order.code, "Seller policy configuration needs review")
    expect(order.metadata).to include("invoice_pending_reason" => "InvoicePolicy::NotConfigured", "confirmation_documents_pending" => true)
    expect(ActionMailer::Base.deliveries.count).to eq(1)
    expect(ActionMailer::Base.deliveries.last.attachments).to be_empty

    post retry_document_finance_document_path(order), params: { confirmed: "1" }
    expect(response).to have_http_status(:unprocessable_content)
    allow(InvoicePolicy).to receive(:snapshot).and_call_original
    approved_finance_policy(admin)
    ticket.update!(price_paise: 1)
    perform_enqueued_jobs(only: [ GenerateOrderDocumentsJob, MailDeliveryJob ]) do
      post retry_document_finance_document_path(order), params: { confirmed: "1" }
    end

    expect(response).to redirect_to(finance_document_path(order))
    expect(order.reload.metadata.fetch("invoice_purchase_lines")).to eq(captured)
    expect(order.metadata).not_to have_key("invoice_pending_reason")
    expect(order.metadata).to include("confirmation_documents_pending" => false)
    invoice = order.invoices.invoice.sole
    expect(invoice.line_items.sole.fetch("total_paise")).to eq(captured.sole.fetch("total_paise"))
    expect(invoice.pdf).to be_attached
    expect(ActionMailer::Base.deliveries.count).to eq(2)
    expect(ActionMailer::Base.deliveries.last.attachments.map(&:filename)).to contain_exactly(invoice.pdf.filename.to_s)
  end

  it "will not retry another order's refund or an unrelated payment event" do
    sign_in_admin(admin)
    approved_finance_policy(admin)
    refund = create(:refund, order:, status: :processed, razorpay_refund_id: "rfnd_original", amount_paise: 100)
    event = create(:payment_event, order:, kind: "refund.processed", amount_paise: 100, raw: {})
    post retry_document_finance_document_path(order), params: { confirmed: "1", refund_id: refund.id, payment_event_id: event.id }
    expect(response).to have_http_status(:unprocessable_content)
    event.update!(raw: { "payload" => { "refund" => { "entity" => { "id" => "rfnd_original" } } } })
    expect { post retry_document_finance_document_path(order), params: { confirmed: "1", refund_id: refund.id, payment_event_id: event.id } }.to have_enqueued_job(ProcessRefundJob).with(refund.id, event.id)
  end
end
