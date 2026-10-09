require "rails_helper"

RSpec.describe "Ticket sale states", type: :request do
  def card_for(type)
    response.parsed_body.css(".ticket-card").find { |card| card.at_css(".ticket-card-title").text == type.name }
  end

  it "marks closed Early Bird and Regular sales without changing remaining stock or purchases" do
    early = create(:ticket_type, name: "Closed Early Bird", slug: "conference-pass-early-bird", active: false, capacity: 30)
    regular = create(:ticket_type, name: "Closed Regular", slug: "conference-pass-regular", active: false, capacity: 140)
    late = create(:ticket_type, name: "Live Late Bird", slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 30)
    create_list(:ticket, 29, ticket_type: early, order: create(:order, :paid))
    create_list(:ticket, 86, ticket_type: regular, order: create(:order, :paid))
    coupon = create(:coupon, percent: 5, discount_paise: nil)
    before = [ TicketType.order(:id).map(&:attributes), Order.order(:id).map(&:attributes), Ticket.order(:id).map(&:attributes), coupon.attributes ]

    get tickets_store_path

    [ early, regular ].each do |type|
      card = card_for(type)
      expect(card.at_css(".ticket-state-badge").text).to eq("sales closed")
      expect(card.at_css(".ticket-unavailable").text).to eq("Sales for this tier have closed.")
      expect(card.at_css(".quantity-stepper")).to be_nil
      expect(card.text).not_to include("Sales open soon.", "This tier has sold out.")
    end
    expect(card_for(early).at_css(".ticket-availability").text.strip).to eq("1 of 30 left")
    expect(card_for(regular).at_css(".ticket-availability").text.strip).to eq("54 of 140 left")
    expect(card_for(late).at_css(".ticket-state-badge").text).to eq("on sale")
    expect(card_for(late).at_css(".ticket-price-amount").text).to eq("₹4,500")
    expect(card_for(late).at_css(".quantity-stepper")).to be_present
    expect([ TicketType.order(:id).map(&:attributes), Order.order(:id).map(&:attributes), Ticket.order(:id).map(&:attributes), coupon.reload.attributes ]).to eq(before)
  end

  it "keeps future starts and other inactive categories coming soon" do
    future = create(:ticket_type, name: "Future Conference", slug: "conference-pass-early-bird", active: false, sales_start_at: 1.day.from_now)
    explore = create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", active: false, requires_conference_pass: true)
    dormant_late = create(:ticket_type, name: "Dormant Late Bird", slug: "conference-pass-late-bird", active: false)

    get tickets_store_path

    [ future, explore, dormant_late ].each do |type|
      card = card_for(type)
      expect(card.at_css(".ticket-state-badge").text).to eq("coming soon")
      expect(card.at_css(".ticket-unavailable").text).to eq("Sales open soon.") unless type.requires_conference_pass?
      expect(card.at_css(".quantity-stepper")).to be_nil
    end
  end

  it "distinguishes exhausted active inventory from an inactive closed tier" do
    exhausted = create(:ticket_type, name: "Exhausted Pass", capacity: 1)
    closed = create(:ticket_type, name: "Closed Empty Regular", slug: "conference-pass-regular", active: false, capacity: 0)
    create(:ticket, ticket_type: exhausted, order: create(:order, :paid))

    get tickets_store_path

    expect(card_for(exhausted).at_css(".ticket-state-badge").text).to eq("sold out")
    expect(card_for(exhausted).at_css(".ticket-unavailable").text).to eq("This tier has sold out.")
    expect(card_for(closed).at_css(".ticket-state-badge").text).to eq("sales closed")
  end

  it "keeps inclusive sale boundaries and closes an elapsed sales window" do
    at = Time.zone.local(2026, 10, 4, 12)
    type = create(:ticket_type, name: "Bounded Pass", sales_start_at: at, sales_end_at: at)

    travel_to(at - 1.second) do
      get tickets_store_path
      expect(card_for(type).at_css(".ticket-state-badge").text).to eq("coming soon")
    end
    travel_to(at) do
      get tickets_store_path
      expect(card_for(type).at_css(".ticket-state-badge").text).to eq("on sale")
      expect(card_for(type).at_css(".quantity-stepper")).to be_present
    end
    travel_to(at + 1.second) do
      get tickets_store_path
      expect(card_for(type).at_css(".ticket-state-badge").text).to eq("sales closed")
      expect(card_for(type).at_css(".ticket-unavailable").text).to eq("Sales for this tier have closed.")
      expect(card_for(type).at_css(".quantity-stepper")).to be_nil
    end
  end
end
