module SeoHelper
  # Clean, query-free canonical for the current page.
  def canonical_url
    "#{request.base_url}#{request.path}"
  end

  # schema.org Event JSON-LD for the conference — powers Google rich results
  # and gives answer engines a structured description of the event.
  def event_structured_data
    {
      "@context" => "https://schema.org",
      "@type" => "Event",
      "name" => "Deccan Queen on Rails 2026",
      "description" => "India's Ruby and Rails conference, October 8–11, 2026 at Hyatt Regency, Pune.",
      "startDate" => "2026-10-08",
      "endDate" => "2026-10-11",
      "eventStatus" => "https://schema.org/EventScheduled",
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "image" => [ image_url("deccan-logo.png") ],
      "url" => root_url,
      "location" => {
        "@type" => "Place",
        "name" => "Hyatt Regency Pune",
        "address" => {
          "@type" => "PostalAddress",
          "addressLocality" => "Pune",
          "addressRegion" => "Maharashtra",
          "addressCountry" => "IN"
        }
      },
      "organizer" => {
        "@type" => "Organization",
        "name" => "Deccan Queen on Rails",
        "url" => "https://deccanqueenonrails.com"
      },
      "offers" => event_offers.presence,
      "performer" => event_performers.presence
    }.compact
  end

  def json_ld_tag(data)
    tag.script(raw(JSON.generate(data).gsub("</", '<\/')), type: "application/ld+json")
  end

  private
    def event_offers
      TicketType.where(hidden: false).order(:position, :id).filter_map do |ticket_type|
        next unless ticket_type.purchasable?

        {
          "@type" => "Offer",
          "name" => ticket_type.name,
          "price" => format("%.2f", ticket_type.price_paise / 100.0),
          "priceCurrency" => "INR",
          "url" => tickets_store_url,
          "availability" => "https://schema.org/InStock",
          "validThrough" => ticket_type.sales_end_at&.iso8601
        }.compact
      end
    end

    def event_performers
      Speaker.publicly_listed.map { |speaker| { "@type" => "Person", "name" => speaker.name } }
    end
end
