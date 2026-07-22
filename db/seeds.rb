admin_email = ENV.fetch("ADMIN_EMAIL") { Rails.env.development? ? "admin@example.com" : raise("ADMIN_EMAIL is required") }
admin_password = ENV.fetch("ADMIN_PASSWORD") { Rails.env.development? ? "password" : raise("ADMIN_PASSWORD is required") }

AdminUser.find_or_create_by!(email: admin_email) { |admin| admin.password = admin_password }

ticket_types = [
  {
    name: "Conference Pass — Early Bird",
    slug: "conference-pass-early-bird",
    description: "Conference pass for Oct 8–9",
    price_paise: 350_000,
    capacity: 30,
    active: true,
    position: 1
  },
  {
    name: "Conference Pass — Regular",
    slug: "conference-pass-regular",
    description: "Conference pass for Oct 8–9",
    price_paise: 550_000,
    capacity: 140,
    active: true,
    position: 2
  },
  {
    name: "Conference Pass — Late Bird",
    slug: "conference-pass-late-bird",
    description: "Conference pass for Oct 8–9",
    price_paise: 500_000,
    capacity: 30,
    active: false,
    position: 3
  },
  {
    name: "Supporter Pass",
    slug: "supporter-pass",
    description: "Back the conference and be named on the site",
    price_paise: 1_000_000,
    capacity: nil,
    active: true,
    position: 4
  },
  {
    name: "Explore Pune Day Add-on",
    slug: "explore-pune-day",
    description: "Explore Pune on Oct 11",
    price_paise: 200_000,
    capacity: 50,
    active: false,
    requires_conference_pass: true,
    position: 5
  },
  {
    name: "Complimentary Pass",
    slug: "complimentary-pass",
    description: "Hidden complimentary ticket",
    price_paise: 0,
    capacity: nil,
    hidden: true,
    position: 6
  }
]

ticket_types.each do |attributes|
  TicketType.find_or_create_by!(slug: attributes[:slug]) { |ticket_type| ticket_type.assign_attributes(attributes) }
end
