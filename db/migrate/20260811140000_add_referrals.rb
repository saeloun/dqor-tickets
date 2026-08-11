class AddReferrals < ActiveRecord::Migration[8.1]
  # Bring-a-friend referrals: each user gets a shareable code; friends who buy
  # via the link get the standing FRIENDS discount (a normal coupon, so it
  # reuses the tested checkout path) and the referrer is credited.
  def up
    execute "SET LOCAL lock_timeout = '8s'"

    unless column_exists?(:users, :referral_code)
      add_column :users, :referral_code, :string
      add_index :users, :referral_code, unique: true
    end

    # Backfill codes (self-contained generator — no app-model dependency).
    User.reset_column_information
    User.where(referral_code: [ nil, "" ]).find_each do |user|
      code = loop do
        candidate = SecureRandom.alphanumeric(7).upcase
        break candidate unless User.exists?(referral_code: candidate)
      end
      user.update_columns(referral_code: code)
    end

    seed_friends_coupon
  end

  def down
    remove_column :users, :referral_code if column_exists?(:users, :referral_code)
  end

  private
    def seed_friends_coupon
      return unless table_exists?(:coupons)

      Coupon.reset_column_information
      Coupon.find_or_create_by!(code: "FRIENDS") do |coupon|
        coupon.percent = 10
        coupon.active = true
      end
    rescue => e
      say "Skipping FRIENDS coupon seed: #{e.class} #{e.message}"
    end
end
