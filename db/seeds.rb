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
    price_paise: 400_000,
    capacity: 140,
    active: false,
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
    name: "Explore Pune Day Add-on",
    slug: "explore-pune-day",
    description: "Explore Pune on Oct 11",
    price_paise: 200_000,
    capacity: 50,
    active: false,
    requires_conference_pass: true,
    position: 4
  },
  {
    name: "Complimentary Pass",
    slug: "complimentary-pass",
    description: "Hidden complimentary ticket",
    price_paise: 0,
    capacity: nil,
    hidden: true,
    position: 5
  }
]

ticket_types.each do |attributes|
  TicketType.find_or_create_by!(slug: attributes[:slug]) { |ticket_type| ticket_type.assign_attributes(attributes) }
end

regular = TicketType.find_by!(slug: "conference-pass-regular")
Coupon.find_or_create_by!(code: "DQFRIENDS") do |coupon|
  coupon.discount_paise = 50_000
  coupon.max_uses = 20
  coupon.ticket_type = regular
end

early_bird = TicketType.find_by!(slug: "conference-pass-early-bird")
Coupon.find_or_create_by!(code: "DQORTEST10") do |coupon|
  coupon.discount_paise = 349_000
  coupon.max_uses = 25
  coupon.ticket_type = early_bird
end

# Coupon.find_or_create_by!(code: "TEAM10") do |coupon|
#   coupon.percent = 10
# end

# Coupon.find_or_create_by!(code: "GIVEAWAY") do |coupon|
#   coupon.percent = 100
#   coupon.max_uses = 5
# end
