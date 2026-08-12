namespace :admins do
  desc "Grant admin access. Usage: bin/rails admins:grant EMAIL=person@example.com [ROLE=admin|desk]"
  task grant: :environment do
    email = ENV.fetch("EMAIL").strip.downcase
    role = ENV.fetch("ROLE", "admin")

    admin = AdminUser.find_or_initialize_by(email: email)
    was_new = admin.new_record?
    admin.role = role
    admin.password = SecureRandom.alphanumeric(24) if was_new
    admin.save!

    puts "#{email} is now #{role}."
    puts "New account — they set a password via \"Forgot password\" on the sign-in page." if was_new
  end

  desc "Revoke admin access. Usage: bin/rails admins:revoke EMAIL=person@example.com"
  task revoke: :environment do
    email = ENV.fetch("EMAIL").strip.downcase
    removed = AdminUser.where(email: email).destroy_all

    puts removed.any? ? "Revoked admin access for #{email}." : "No admin found for #{email}."
  end

  desc "List admins and their roles."
  task list: :environment do
    AdminUser.order(:role, :email).each { |admin| puts "#{admin.role.ljust(6)} #{admin.email}" }
  end
end
