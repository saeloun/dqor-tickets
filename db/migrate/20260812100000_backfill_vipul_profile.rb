class BackfillVipulProfile < ActiveRecord::Migration[8.1]
  EMAIL = "vipul@saeloun.com".freeze

  # Known, public handles. Only applied to fields that are currently blank —
  # anything Vipul has already set is left untouched.
  FIELDS = {
    website: "https://vipulnsward.com",
    x_username: "vipulnsward",
    github: "vipulnsward",
    linkedin: "vipulnsward"
  }.freeze

  BIO = "Founder at Saeloun. Ruby, Rails, and React. Organizing Deccan Queen on Rails.".freeze

  def up
    execute "SET LOCAL lock_timeout = '8s'"
    return unless table_exists?(:users)

    user = User.find_by("lower(email) = ?", EMAIL)
    return unless user

    updates = FIELDS.reject { |field, _| user.public_send(field).present? }
    updates[:bio] = BIO if user.bio.blank?

    user.update!(updates) if updates.any?
  rescue => e
    say "Skipped Vipul profile backfill: #{e.class} #{e.message}"
  end

  def down
  end
end
