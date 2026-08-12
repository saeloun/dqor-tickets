class ReduceReferralDiscountToFive < ActiveRecord::Migration[8.1]
  # Bring-a-friend discount: 10% -> 5% for everyone sharing their link.
  def up
    execute "SET LOCAL lock_timeout = '8s'"
    Coupon.where(code: "FRIENDS").update_all(percent: 5) if table_exists?(:coupons)
  end

  def down
    Coupon.where(code: "FRIENDS").update_all(percent: 10) if table_exists?(:coupons)
  end
end
