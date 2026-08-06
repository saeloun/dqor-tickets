class CreateZendeskSponsorCoupon < ActiveRecord::Migration[8.1]
  # Sponsor code for Zendesk: 100% off (free ticket), capped at 5 redemptions.
  # Idempotent so it is safe to re-run; rotate or deactivate it in Avo once
  # the sponsor has claimed their tickets.
  def up
    Coupon.find_or_create_by!(code: "ZENDESK") do |coupon|
      coupon.percent = 100
      coupon.max_uses = 5
      coupon.active = true
    end
  end

  def down
    coupon = Coupon.find_by(code: "ZENDESK")
    coupon.destroy if coupon && coupon.uses_count.zero?
  end
end
