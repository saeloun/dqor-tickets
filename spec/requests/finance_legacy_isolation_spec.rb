require "rails_helper"

RSpec.describe "Finance isolation from organizer-owned commerce", type: :request do
  let!(:organization) { Organization.create!(name: "Isolated organizer", slug: "isolated-organizer") }
  let!(:event) { organization.events.create!(title: "Isolated event", slug: "isolated-event") }
  let!(:order) do
    create(:order, :paid, event_id: event.id, user_id: create(:user_for_free_pilot).id, total_paise: 0,
      metadata: { "invoice_pending_reason" => "pending", "billing_request_nonce" => "synthetic-private-nonce", "billing_address" => "Tenant private address" })
  end
  let(:billing) { { billing_address: "Replacement address", billing_state_name: "Maharashtra", billing_state_code: "27" } }

  it "excludes tenant documents from the administrator queue and code search" do
    sign_in_admin
    get finance_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(order.code, "Tenant private address")
    get finance_documents_path, params: { code: order.code }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Tenant private address", finance_document_path(order))
  end

  it "rejects tenant detail, edits, follow-up links and document retries without changes or jobs" do
    sign_in_admin
    original = order.attributes
    expect {
      get finance_document_path(order)
      expect(response).to have_http_status(:not_found)
      patch finance_document_path(order), params: { billing:, verified: "1", billing_revision: 0 }
      expect(response).to have_http_status(:not_found)
      post request_details_finance_document_path(order)
      expect(response).to have_http_status(:not_found)
      post retry_document_finance_document_path(order), params: { confirmed: "1" }
      expect(response).to have_http_status(:not_found)
    }.not_to change { enqueued_jobs.size }
    expect(order.reload.attributes).to eq(original)
  end

  it "rejects even correctly signed tenant buyer links without private content or mutation" do
    token = order.generate_token_for(:billing_details)
    original = order.attributes
    expect {
      get billing_details_path, params: { token: }
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Tenant private address")
      patch billing_details_path, params: { token:, billing:, billing_revision: 0 }
      expect(response).to have_http_status(:not_found)
    }.not_to change { enqueued_jobs.size }
    expect(order.reload.attributes).to eq(original)
  end

  it "rejects shared billing and invoice operations before reading or writing tenant data" do
    original = order.attributes
    expect { BillingDetails.for_order(order) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { BillingDetails.update_order!(order, billing, source: "test", revision: 0) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { Invoice.issue_for!(order) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { Invoice.buyer_snapshot(order) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(order.reload.attributes).to eq(original)
    expect(order.invoices).to be_empty
  end
end
