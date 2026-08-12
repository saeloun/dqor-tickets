class CreateSaelounTeamCoupon < ActiveRecord::Migration[8.1]
  # A 100%-off code for the Saeloun team: 10 free passes (10 redemptions).
  # A 100% coupon takes the order to ₹0, which checks out as a comp (no
  # Razorpay). max_uses caps the number of orders that can redeem it.
  def up
    execute "SET LOCAL lock_timeout = '8s'"
    return unless table_exists?(:coupons)

    Coupon.reset_column_information
    Coupon.find_or_create_by!(code: "SAELOUNTEAM") do |coupon|
      coupon.percent  = 100
      coupon.max_uses = 10
      coupon.active   = true
    end
  rescue => e
    say "Skipping Saeloun team coupon: #{e.class} #{e.message}"
  end

  def down
    return unless table_exists?(:coupons)

    Coupon.where(code: "SAELOUNTEAM").delete_all
  end
end
