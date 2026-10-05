require "rails_helper"

RSpec.describe "Order confirmation programme", type: :mailer do
  it "includes approved public programme context in both parts while retaining selected venues and private links" do
    order = create(:order, :paid)
    conference = create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", venue_name: "Synthetic Conference Venue", venue_address: "Synthetic Conference Address")
    girls = create(:ticket_type, name: "Rails Girls Pune", slug: "rails-girls-pune", venue_name: "Synthetic Workshop Venue", venue_address: "Synthetic Workshop Address")
    create(:ticket, order: order, ticket_type: conference)
    create(:ticket, order: order, ticket_type: girls)
    before = [ order.attributes, order.tickets.order(:id).map(&:attributes) ]
    deliveries = ActionMailer::Base.deliveries.size

    mail = OrderMailer.confirmation(order, documents_pending: true)
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      expect(body).to include("October 8–9", "October 8", "October 10", "October 11")
      expect(body).to include("Conference", "afterparty", "Rails Girls", "optional Explore Pune Day")
      expect(body).to include("separate events", "ticket details", "https://deccanqueenonrails.com/schedule")
      expect(body).to include(conference.venue_name, conference.venue_address, girls.venue_name, girls.venue_address)
      expect(body).to include(order_url(order.code))
      order.tickets.each { |ticket| expect(body).to include(ticket_claim_url(ticket.claim_token)) }
      expect(body).not_to include("hotel", "Hotel")
    end
    expect(mail.attachments).to be_empty
    expect(ActionMailer::Base.deliveries.size).to eq(deliveries)
    expect([ order.reload.attributes, order.tickets.order(:id).map(&:attributes) ]).to eq(before)
  end
end
