require "rails_helper"

RSpec.describe "Order email frame rendering", type: :request do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def expect_email_exclusions(order, attendee_email)
    [ order.email, attendee_email ].each do |email|
      expect(response.body).to include("<!--email_off-->#{ERB::Util.html_escape(email)}<!--/email_off-->")
    end
    expect(response.parsed_body.at_css("turbo-frame#order_status")).to be_present
  end

  it "excludes displayed buyer and attendee addresses in a direct Turbo frame response" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:)

    get order_path(order.code), headers: { "Turbo-Frame" => "order_status" }

    expect(response).to have_http_status(:ok)
    expect_email_exclusions(order, ticket.attendee_email)
  end

  it "retains email exclusions when assignment validation renders a 422 frame" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:)
    before = ticket.attributes

    patch assign_order_ticket_path(order.code, ticket), headers: { "Turbo-Frame" => "order_status" }, params: {
      ticket: { attendee_name: ticket.attendee_name, attendee_email: "invalid<email@example.test" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Attendee email is invalid")
    expect_email_exclusions(order, ticket.attendee_email)
    ticket.reload
    expect(ticket.attributes).to eq(before)
  end

  it "keeps stored email text HTML escaped inside the exclusions" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:)
    order.update_column(:email, '<img src=x onerror="alert(1)">@example.test')
    ticket.update_column(:attendee_email, '<script>alert(2)</script>@example.test')

    get order_path(order.code), headers: { "Turbo-Frame" => "order_status" }

    expect(response).to have_http_status(:ok)
    expect_email_exclusions(order.reload, ticket.reload.attendee_email)
    expect(response.parsed_body.css("img[onerror]")).to be_empty
    expect(response.parsed_body.css("script").map(&:text)).not_to include("alert(2)")
  end
end
