class CreateOrganizerPromoCoupon < ActiveRecord::Migration[8.1]
  # Shared organiser/referral code for social media and friends: 10% off any
  # pass, whole order, capped at 30 redemptions. Idempotent so it is safe to
  # re-run; the organiser can adjust or deactivate it in Avo afterwards.
  def up
    Coupon.find_or_create_by!(code: "DQOR10") do |coupon|
      coupon.percent = 10
      coupon.max_uses = 30
      coupon.active = true
    end
  end

  def down
    coupon = Coupon.find_by(code: "DQOR10")
    coupon.destroy if coupon && coupon.uses_count.zero?
  end
end
