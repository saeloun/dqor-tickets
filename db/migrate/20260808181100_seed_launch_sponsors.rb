class SeedLaunchSponsors < ActiveRecord::Migration[8.1]
  # Mirrors the sponsors already featured on the home page (#sponsors) so the
  # dedicated /sponsors page shows the real, live sponsors instead of a
  # "coming soon" empty state. Logos are served from static public files
  # (public/dqor/*) via logo_path, so they survive redeploys regardless of the
  # Active Storage backend.
  #
  # This runs in the boot-time db:prepare (before Puma), so it is bounded by
  # timeouts and fully rescued: a launch-seed hiccup must never hang or fail
  # the deploy. Worst case the sponsors are seeded later (re-run or via Avo).
  def up
    return unless table_exists?(:sponsors)

    execute "SET LOCAL lock_timeout = '8s'"
    execute "SET LOCAL statement_timeout = '30s'"
    Sponsor.reset_column_information

    [
      { name: "Saeloun",   tier: "platinum", position: 1,
        url: "https://saeloun.com",  logo_path: "/dqor/saeloun-logo.png",
        blurb: "A Ruby on Rails consultancy building and maintaining ambitious products." },
      { name: "Typesense", tier: "wifi",     position: 2,
        url: "https://typesense.org", logo_path: "/dqor/typesense-logo.png" }
    ].each do |attrs|
      sponsor = Sponsor.find_or_initialize_by(name: attrs[:name])
      # Only fill blanks so an admin's later edits (via Avo) are never clobbered.
      sponsor.tier      = attrs[:tier]      if sponsor.tier.blank?
      sponsor.position  = attrs[:position]  if sponsor.position.to_i.zero?
      sponsor.url       = attrs[:url]       if sponsor.url.blank?
      sponsor.logo_path = attrs[:logo_path] if sponsor.logo_path.blank?
      sponsor.blurb     = attrs[:blurb]     if sponsor.blurb.blank? && attrs[:blurb].present?
      sponsor.published = true
      sponsor.save!
    end
  rescue => e
    say "Skipping launch sponsor seed: #{e.class} #{e.message}"
  end

  def down
    return unless table_exists?(:sponsors)

    Sponsor.where(name: %w[Saeloun Typesense]).delete_all
  end
end
