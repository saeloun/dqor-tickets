FactoryBot.define do
  sequence(:email) { |number| "person#{number}@example.com" }
  sequence(:slug) { |number| "ticket-type-#{number}" }
  sequence(:coupon_code) { |number| "CODE#{number}" }
  sequence(:razorpay_event_id) { |number| "event_#{number}" }
  sequence(:invoice_number) { |number| "DQOR/2026-27/#{format('%04d', number)}" }
  sequence(:organizer_slug) { |number| "organizer-#{number}" }
  sequence(:event_slug) { |number| "event-#{number}" }
  sequence(:user_id)

  factory :admin_user do
    email { generate(:email) }
    password { "password123" }
  end

  factory :account do
    name { "Saeloun" }
    billing_email { generate(:email) }
    country { "IN" }
    status { "active" }
  end

  factory :organizer do
    association :account
    name { "Deccan Queen on Rails" }
    slug { generate(:organizer_slug) }
    default_currency { "INR" }
    default_timezone { "Asia/Kolkata" }
    payout_mode { "direct" }
    status { "active" }
  end

  factory :event do
    association :organizer
    title { "Deccan Queen on Rails 2026" }
    slug { generate(:event_slug) }
    status { "draft" }
    format { "in_person" }
    starts_at { Time.zone.local(2026, 10, 8) }
    ends_at { Time.zone.local(2026, 10, 11) }
    timezone { "Asia/Kolkata" }
    venue_state_code { "27" }
    currency { "INR" }
    visibility { "public" }
  end

  factory :tax_profile do
    association :organizer
    gstin { "27AAPFU0939F1ZV" }
    legal_name { "Saeloun Software Pvt Ltd" }
    registered_state_code { "27" }
    address { "Pune, Maharashtra" }
    country { "IN" }
    sac_code { "998596" }
    tax_rate_bp { 1800 }
    tax_inclusive { true }
    invoice_prefix { "DQOR/" }
    cn_prefix { "DQOR-CN/" }
    invoice_timing { "immediate" }
  end

  factory :membership do
    association :organizer
    user_id
    role { "viewer" }
  end

  factory :invoice_sequence do
    association :organizer
    series { "invoice" }
    fiscal_year { "2026-27" }
    last_number { 0 }
  end

  factory :ticket_type do
    name { "Conference Pass" }
    slug
    price_paise { 350_000 }
    capacity { 10 }
    min_per_order { 1 }
    active { true }
  end

  factory :coupon do
    code { generate(:coupon_code) }
    discount_paise { 50_000 }
    max_uses { 20 }
    association :ticket_type
    active { true }
  end

  factory :order do
    email { generate(:email) }
    buyer_name { "Ada Lovelace" }
    buyer_phone { "9999999999" }
    status { :pending }
    total_paise { 350_000 }
    expires_at { 30.minutes.from_now }

    trait :paid do
      status { :paid }
    end
  end

  factory :ticket do
    association :order
    association :ticket_type
    price_paise { ticket_type.price_paise }
    attendee_name { "Ada Lovelace" }
    attendee_email { generate(:email) }
  end

  factory :payment_event do
    association :order
    razorpay_event_id { generate(:razorpay_event_id) }
    kind { "order.paid" }
    amount_paise { order.total_paise }
  end

  factory :refund do
    association :order
    amount_paise { 100_000 }
    status { "pending" }
  end

  factory :invoice do
    association :order
    number { generate(:invoice_number) }
    issued_on { Date.new(2026, 7, 19) }
    buyer_snapshot { {} }
    line_items { [] }
    kind { :invoice }
  end
end
