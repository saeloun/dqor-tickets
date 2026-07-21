require "rails_helper"

RSpec.describe "Ticket assignments", type: :request do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  it "lets the buyer assign a ticket from the paid order" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: nil, attendee_email: nil)

    patch assign_order_ticket_path(order.code, ticket), params: {
      ticket: {
        attendee_name: "Grace Hopper",
        attendee_email: "grace@example.com",
        dietary_preference: "No peanuts",
        childcare_needed: "1"
      }
    }

    expect(response).to redirect_to(order_path(order.code))
    expect(ticket.reload).to have_attributes(
      attendee_name: "Grace Hopper",
      attendee_email: "grace@example.com",
      dietary_preference: "No peanuts",
      childcare_needed: true
    )
    expect(ticket).to be_assigned
  end

  it "uses a claim token to assign exactly one ticket" do
    order = create(:order, :paid)
    ticket, other_ticket = create_list(:ticket, 2, order:, attendee_name: nil, attendee_email: nil)

    get ticket_claim_path(ticket.claim_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claim your ticket", ticket.ticket_type.name)

    expect do
      patch ticket_claim_path(ticket.claim_token), params: {
        ticket: { attendee_name: "Ada Lovelace", attendee_email: "ada@example.com" }
      }
    end.to have_enqueued_mail(OrderMailer, :ticket).with(ticket)

    expect(response).to redirect_to(ticket_claim_path(ticket.claim_token))
    expect(ticket.reload).to be_assigned
    expect(other_ticket.reload).not_to be_assigned
  end
end
