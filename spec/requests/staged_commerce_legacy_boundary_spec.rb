require "rails_helper"

RSpec.describe "Staged inventory and legacy checkout", type: :request do
  let!(:organization) { Organization.create!(name: "New organizer", slug: "new-organizer") }
  let!(:event) { organization.events.create!(title: "New event", slug: "new-event") }
  let!(:type) { create(:ticket_type, event_id: event.id, name: "Private staged inventory", hidden: true, active: false) }

  it "never lists event-owned draft inventory on the legacy store" do
    get tickets_store_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(type.name)
  end

  it "rejects forged legacy checkout selection without creating an order or contacting a provider" do
    expect(Razorpay::Order).not_to receive(:create)
    expect {
      post orders_path, params: { checkout: { email: "buyer@example.test", buyer_name: "Buyer", quantities: { type.id.to_s => "1" } } }
    }.not_to change(Order, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include(type.name)
  end

  it "adds no organizer commerce route" do
    expect { Rails.application.routes.recognize_path("/organizer/organizations/#{organization.id}/events/#{event.id}/orders", method: :post) }.to raise_error(ActionController::RoutingError)
  end
end
