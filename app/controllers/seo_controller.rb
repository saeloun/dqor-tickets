class SeoController < ApplicationController
  allow_unauthenticated_access

  def robots
    render plain: robots_txt, content_type: "text/plain"
  end

  def sitemap
    render xml: sitemap_xml, content_type: "application/xml"
  end

  def llms
    render plain: llms_txt, content_type: "text/plain"
  end

  private
    def robots_txt
      <<~TXT
        User-agent: *
        Allow: /
        Disallow: /avo
        Disallow: /account
        Disallow: /orders
        Disallow: /claim
        Disallow: /checkin
        Disallow: /concierge
        Disallow: /tickets/find
        Disallow: /tickets/access
        Disallow: /tickets/mine

        Sitemap: #{request.base_url}/sitemap.xml
      TXT
    end

    def sitemap_xml
      locations = sitemap_paths.map { |path| "  <url><loc>#{request.base_url}#{path}</loc></url>" }
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{locations.join("\n")}
        </urlset>
      XML
    end

    def sitemap_paths
      static = [
        root_path, tickets_store_path, speakers_path, sponsors_path,
        schedule_path, faq_path, updates_path, info_pages_path,
        community_path, calendar_path
      ]
      speakers = Speaker.publicly_listed.map { |speaker| speaker_path(speaker) }
      pages = InfoPage.published.map { |page| info_page_path(page) }
      (static + speakers + pages).uniq
    end

    def llms_txt
      <<~TXT
        # Deccan Queen on Rails 2026

        > India's Ruby and Rails conference, October 8–11, 2026 at Hyatt Regency, Pune.
        > Rooted in Pune's heritage, bringing Rubyists from across India together with invited voices from around the world.

        - Dates: October 8–11, 2026
        - Venue: Hyatt Regency, Pune, India
        - Focus: Ruby, Ruby on Rails, and the wider Ruby ecosystem
        - Tickets and registration: #{request.base_url}/tickets
        - Home: #{request.base_url}/

        ## Key pages
        - Tickets and passes: #{request.base_url}/tickets
        - Speakers: #{request.base_url}/speakers
        - Schedule: #{request.base_url}/schedule
        - Sponsors: #{request.base_url}/sponsors
        - Updates and announcements: #{request.base_url}/updates
        - FAQ: #{request.base_url}/faq

        ## About
        Deccan Queen on Rails is a community Ruby conference held in Pune, India. Alongside the
        main two-day conference it runs Rails Girls Pune, an Explore Pune Day, and heritage
        experiences. The event is organised by Saeloun.
      TXT
    end
end
