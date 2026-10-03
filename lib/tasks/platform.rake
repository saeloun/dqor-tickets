namespace :platform do
  desc "Print a read-only Saeloun/Vipul provisioning proposal; never grants access"
  task seed_dry_run: :environment do
    email = ENV["PLATFORM_OWNER_EMAIL"].to_s.strip.downcase
    abort "Set PLATFORM_OWNER_EMAIL to Vipul's reviewed, exact account email" if email.blank?
    user = User.find_by(email: email)
    proposal = {
      dry_run: true,
      organization: { name: "Saeloun", slug: "saeloun", existing_id: Organization.find_by(slug: "saeloun")&.id },
      proposed_owner: { requested_name: "Vipul", email: email, existing_user_id: user&.id },
      grants_applied: 0,
      blockers: [ "Confirm exact account identity and approved roster before provisioning", "Review DQOR event mapping and commerce backfill separately" ]
    }
    puts JSON.pretty_generate(proposal)
  end
end
