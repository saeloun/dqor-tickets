require "rails_helper"

RSpec.describe "Private buyer billing follow-up", type: :request do
  let(:order) { create(:order, :paid, metadata: { "billing_request_nonce" => "synthetic-nonce" }) }
  let(:billing) { { billing_address: "Private address", billing_state_name: "Maharashtra", billing_state_code: "27" } }

  it "accepts an expiring one-use link without exposing the admin interface or triggering issuance" do
    token = order.generate_token_for(:billing_details)
    get billing_details_path, params: { token: }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Seller policy reviews")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect { patch billing_details_path, params: { token:, billing:, billing_revision: 0 } }.not_to change(Invoice, :count)
    expect(response.body).to include("Billing details received")
    expect(order.reload.metadata["billing_address"]).to eq("Private address")
    expect(order.metadata["billing_updates"].sole["source"]).to eq("buyer_link")
    patch billing_details_path, params: { token:, billing:, billing_revision: 1 }
    expect(response).to have_http_status(:not_found)
  end

  it "rejects tampered, expired and superseded links" do
    token = order.generate_token_for(:billing_details)
    get billing_details_path, params: { token: "#{token}tampered" }
    expect(response).to have_http_status(:not_found)
    travel 8.days do
      get billing_details_path, params: { token: }
      expect(response).to have_http_status(:not_found)
    end
    order.update!(metadata: order.metadata.merge("billing_request_nonce" => "replacement"))
    get billing_details_path, params: { token: }
    expect(response).to have_http_status(:not_found)
  end

  it "rejects links once any invoice has been issued" do
    token = order.generate_token_for(:billing_details)
    create(:ticket, order:)
    invoice = Invoice.issue_for!(order)
    patch billing_details_path, params: { token:, billing:, billing_revision: 0 }
    expect(response).to have_http_status(:not_found)
    expect(invoice.reload.buyer_snapshot).not_to have_key("billing_address")
  end

  it "keeps a link usable after incomplete data and prevents financial field injection" do
    order.update!(gstin: "27AAAAA0000A1Z5", gst_legal_name: "Synthetic Buyer", billing_state_code: "27")
    token = order.generate_token_for(:billing_details)
    patch billing_details_path, params: { token:, billing: { billing_address: "" }, billing_revision: 0 }
    expect(response).to have_http_status(:unprocessable_content)
    patch billing_details_path, params: { token:, billing: billing.merge(total_paise: 0, status: "canceled", gstin: "29AAAAA0000A1Z5"), billing_revision: 0 }
    expect(response).to have_http_status(:ok)
    expect(order.reload).to be_paid
    expect(order.total_paise).to eq(350_000)
    expect(order.gstin).to eq("27AAAAA0000A1Z5")
  end

  it "lets admins create a replacement link but sends no messages" do
    sign_in_admin
    previous_token = order.generate_token_for(:billing_details)
    expect { post request_details_finance_document_path(order) }.not_to have_enqueued_job(MailDeliveryJob)
    expect(response.body).to include("Private billing follow-up link", "No message has been sent")
    get billing_details_path, params: { token: previous_token }
    expect(response).to have_http_status(:not_found)
  end
end
