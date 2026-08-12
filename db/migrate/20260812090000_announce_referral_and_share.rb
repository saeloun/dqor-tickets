class AnnounceReferralAndShare < ActiveRecord::Migration[8.1]
  # In-app notification about the 5% bring-a-friend discount + new social
  # share buttons. Published immediately (visible at /updates and on the
  # account hub) but intentionally left un-emailed: sending to every ticket
  # holder is a one-click Avo action ("Email to ticket holders") the owner
  # triggers when ready. Idempotent on the title.
  TITLE = "Share your pass, save 5% — plus one-tap sharing in the app".freeze

  BODY = <<~BODY.freeze
    Two quick updates for everyone who already has a ticket.

    Bring a friend, both win. Every attendee now has a personal referral link in their account. Share it, and anyone who books through it gets 5% off their pass — you'll also see who joins from your link.

    Share in one tap. Your account now has Share on X, LinkedIn, and WhatsApp buttons that pre-fill a message with your link, so telling your team or your timeline takes a single tap.

    You'll find your link under "Bring a friend" when you open your account. See you in Pune, October 8–11.

    — Vipul
  BODY

  def up
    execute "SET LOCAL lock_timeout = '8s'"
    return unless table_exists?(:announcements)

    Announcement.reset_column_information
    Announcement.find_or_create_by!(title: TITLE) do |announcement|
      announcement.body = BODY
      announcement.published = true
      announcement.published_at = Time.current
    end
  rescue => e
    say "Skipped referral announcement: #{e.class} #{e.message}"
  end

  def down
    return unless table_exists?(:announcements)

    Announcement.where(title: TITLE).destroy_all
  end
end
