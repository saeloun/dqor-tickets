require "rails_helper"

RSpec.describe "Order polling state", type: :request do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  %i[pending paid expired canceled].each do |status|
    it "places #{status} polling state on content replaced by the frame" do
      order = create(:order, status:)
      create(:ticket, order:) if status == :paid

      get order_path(order.code), headers: { "Turbo-Frame" => "order_status" }

      expect(response).to have_http_status(:ok)
      frame = response.parsed_body.at_css("turbo-frame#order_status")
      expect(frame["data-controller"]).to be_nil
      card = frame.at_css(".status-card[data-controller='poll']")
      expect(card["data-poll-url-value"]).to eq(order_path(order.code))
      expect(card["data-poll-active-value"]).to eq((status == :pending).to_s)
    end
  end
end
