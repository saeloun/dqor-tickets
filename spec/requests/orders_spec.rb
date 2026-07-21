require "rails_helper"

RSpec.describe "Orders", type: :request do
  let(:ticket_type) { create(:ticket_type, slug: "conference-pass-regular", price_paise: 400_000, capacity: 5, max_per_order: 4) }
  let(:razorpay_url) { "https://api.razorpay.com/v1/orders" }

  def checkout_params(quantities: { ticket_type.id.to_s => "1" }, **attributes)
    {
      checkout: {
        email: "buyer@example.com",
        buyer_name: "Buyer",
        buyer_phone: "9999999999",
        quantities:
      }.merge(attributes)
    }
  end

  def stub_razorpay_order(id: "order_test")
    stub_request(:post, razorpay_url).to_return(
      status: 200,
      body: { entity: "order", id:, amount: 400_000, currency: "INR" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "creates a held order with an unassigned ticket and Razorpay order" do
    stub_razorpay_order

    expect { post orders_path, params: checkout_params }
      .to change(Order, :count).by(1)
      .and change(Ticket, :count).by(1)

    order = Order.last
    expect(response).to have_http_status(:created)
    expect(response.body).to include("Pay securely with Razorpay", order.code)
    expect(order.razorpay_order_id).to eq("order_test")
    expect(order.payment_events.sole).to have_attributes(kind: "order_created", level: "info", mode: "test")
    expect(order.tickets.sole).to have_attributes(attendee_name: nil, attendee_email: nil, assigned_at: nil)
    expect(order.tickets.sole).not_to be_assigned
    expect(order.tickets.sole.pdf).not_to be_attached
    expect(a_request(:post, razorpay_url).with(body: hash_including("amount" => "400000", "currency" => "INR", "receipt" => order.code))).to have_been_made.once
  end

  it "rejects a sold-out selection without calling Razorpay" do
    create(:ticket, ticket_type:, order: create(:order, :paid))
    ticket_type.update!(capacity: 1)

    expect { post orders_path, params: checkout_params }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("does not have 1 tickets available")
    expect(a_request(:post, razorpay_url)).not_to have_been_made
  end

  it "applies a coupon before creating the Razorpay order" do
    coupon = create(:coupon, code: "POOL", ticket_type:, discount_paise: 50_000)
    stub_razorpay_order

    post orders_path, params: checkout_params(coupon_code: "pool")

    expect(response).to have_http_status(:created)
    expect(Order.last.total_paise).to eq(350_000)
    expect(Order.last.coupon).to eq(coupon)
    expect(a_request(:post, razorpay_url).with(body: hash_including("amount" => "350000"))).to have_been_made.once
  end

  it "enforces the conference-pass gate" do
    add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true, price_paise: 200_000)

    post orders_path, params: checkout_params(quantities: { add_on.id.to_s => "1" })

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("a paid conference pass is required")
  end

  it "allows Explore Pune Day with a conference pass in the same cart" do
    add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true, price_paise: 200_000)
    stub_razorpay_order

    post orders_path, params: checkout_params(quantities: { ticket_type.id.to_s => "1", add_on.id.to_s => "1" })

    expect(response).to have_http_status(:created)
    expect(Order.last.tickets.count).to eq(2)
  end

  it "allows a standalone add-on for an existing paid conference order" do
    paid_order = create(:order, :paid, email: "owner@example.com")
    create(:ticket, order: paid_order, ticket_type:)
    add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true, price_paise: 200_000)
    stub_razorpay_order

    post orders_path, params: checkout_params(
      quantities: { add_on.id.to_s => "1" },
      conference_order_code: paid_order.code,
      conference_order_email: "OWNER@example.com"
    )

    expect(response).to have_http_status(:created)
    expect(Order.last.tickets.sole.ticket_type).to eq(add_on)
  end

  it "confirms a free order without calling Razorpay" do
    allow(PdfRenderer).to receive(:render)
    free = create(:ticket_type, name: "Community Pass", price_paise: 0)

    expect { post orders_path, params: checkout_params(quantities: { free.id.to_s => "1" }) }
      .to have_enqueued_job(DeliverOrderConfirmationJob).with(kind_of(Order))

    order = Order.last
    expect(response).to have_http_status(:created)
    expect(order).to be_paid
    expect(order.payment_events.sole.kind).to eq("comp")
    expect(order.invoices.invoice.count).to eq(1)
    expect(PdfRenderer).not_to have_received(:render)
    expect(a_request(:post, razorpay_url)).not_to have_been_made
  end

  it "confirms a sub-rupee order without calling Razorpay" do
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
    low_cost = create(:ticket_type, name: "Token Pass", price_paise: 99)

    post orders_path, params: checkout_params(quantities: { low_cost.id.to_s => "1" })

    expect(Order.last).to be_paid
    expect(Order.last.payment_events.sole.amount_paise).to eq(99)
    expect(a_request(:post, razorpay_url)).not_to have_been_made
  end

  it "expires the inventory hold when Razorpay is unavailable" do
    stub_request(:post, razorpay_url).to_timeout

    post orders_path, params: checkout_params

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please try again.")
    expect(Order.last).to be_expired
  end

  it "expires a pending free order after a Ferrum failure" do
    free = create(:ticket_type, name: "Community Pass", price_paise: 0)
    allow_any_instance_of(Order).to receive(:complete_comp!).and_raise(Ferrum::Error, "render failed")

    post orders_path, params: checkout_params(quantities: { free.id.to_s => "1" })

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please try again.")
    expect(Order.last).to be_expired
  end

  it "returns a friendly 404 for an unknown order code" do
    get order_path("UNKNOWN3")

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("The page you were looking for doesn't exist")
  end
end
