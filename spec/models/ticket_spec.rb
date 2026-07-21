require "rails_helper"

RSpec.describe Ticket, type: :model do
  it "generates a unique 24-character base58 secret" do
    ticket = create(:ticket)

    expect(ticket.secret).to match(/\A[1-9A-HJ-NP-Za-km-z]{24}\z/)
  end

  it "generates a unique 24-character base58 claim token" do
    ticket = create(:ticket)

    expect(ticket.claim_token).to match(/\A[1-9A-HJ-NP-Za-km-z]{24}\z/)
  end

  it "assigns the attendee, generates the PDF, and queues the attendee email" do
    ticket = create(:ticket, attendee_name: nil, attendee_email: nil)
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")

    expect do
      ticket.assign!(
        attendee_name: "Grace Hopper",
        attendee_email: "GRACE@example.com",
        dietary_preference: "No peanuts",
        childcare_needed: true
      )
    end.to have_enqueued_mail(OrderMailer, :ticket).with(ticket)

    expect(ticket.reload).to be_assigned
    expect(ticket).to have_attributes(
      attendee_name: "Grace Hopper",
      attendee_email: "grace@example.com",
      dietary_preference: "No peanuts",
      childcare_needed: true
    )
    expect(ticket.assigned_at).to be_within(2.seconds).of(Time.current)
    expect(ticket.pdf).to be_attached
  end

  it "rejects assignment of a canceled ticket" do
    ticket = create(:ticket, canceled_at: Time.current)

    expect do
      ticket.assign!(attendee_name: "Grace Hopper", attendee_email: "grace@example.com")
    end.to raise_error(described_class::Canceled)
  end

  it "regenerates and re-emails a reassigned ticket" do
    ticket = create(:ticket)
    allow(PdfRenderer).to receive(:render).and_return("%PDF-first", "%PDF-second")

    2.times do |index|
      expect do
        ticket.assign!(attendee_name: "Attendee #{index}", attendee_email: "attendee#{index}@example.com")
      end.to have_enqueued_mail(OrderMailer, :ticket).with(ticket)
    end

    expect(PdfRenderer).to have_received(:render).twice
    expect(ticket.reload).to have_attributes(attendee_name: "Attendee 1", attendee_email: "attendee1@example.com")
    expect(ticket.pdf.download).to eq("%PDF-second")
  end

  it "records separate per-day check-ins" do
    ticket = create(:ticket)

    first = ticket.check_in!(Date.new(2026, 10, 8))
    second = ticket.check_in!(Date.new(2026, 10, 9))

    expect(ticket.reload.checked_in_at).to eq("2026-10-08" => first, "2026-10-09" => second)
  end

  it "raises with the prior timestamp on a duplicate check-in" do
    ticket = create(:ticket)
    checked_in_at = ticket.check_in!(Date.new(2026, 10, 8))

    expect { ticket.check_in!(Date.new(2026, 10, 8)) }
      .to raise_error(described_class::AlreadyCheckedIn) { |error| expect(error.checked_in_at).to eq(checked_in_at) }
  end

  it "rejects a canceled ticket" do
    ticket = create(:ticket, canceled_at: Time.current)

    expect { ticket.check_in!(Date.new(2026, 10, 8)) }.to raise_error(described_class::Canceled)
  end
end
