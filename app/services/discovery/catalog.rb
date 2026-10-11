module Discovery
  class Catalog
    Result = Data.define(:filters, :period_counts, :total, :page, :listings, :source_count)

    def self.call(params)
      filters = {
        q: params[:q].to_s.strip.first(100),
        topic: %w[ruby react javascript developer].include?(params[:topic]) ? params[:topic] : "",
        region: %w[india pune].include?(params[:region]) ? params[:region] : "global",
        view: params[:view] == "cards" ? "cards" : "rows",
        period: %w[all upcoming past uncertain weekend].include?(params[:period]) ? params[:period] : "upcoming"
      }
      listings = Listing.all
      if filters[:q].present?
        query = "%#{Listing.sanitize_sql_like(filters[:q])}%"
        listings = listings.where("title ILIKE :query OR city ILIKE :query", query: query)
      end
      listings = listings.where("? = ANY (topics)", filters[:topic]) if filters[:topic].present?
      listings = listings.where(country_code: "IN") if %w[india pune].include?(filters[:region])
      listings = listings.where("LOWER(city) = ?", "pune") if filters[:region] == "pune"
      counts = %w[all upcoming past uncertain].index_with { |period| listings.in_period(period).count }
      listings = listings.in_period(filters[:period])
      total = listings.count
      page = [ [ params[:page].to_i, 1 ].max, 1_000 ].min
      order = %w[upcoming weekend].include?(filters[:period]) ? "starts_on ASC NULLS LAST" : "starts_on DESC NULLS LAST"
      listings = listings.includes(:primary_source, references: :source).order(Arel.sql(order), :title, :id).limit(24).offset((page - 1) * 24)
      Result.new(filters: filters, period_counts: counts, total: total, page: page, listings: listings, source_count: Source.count)
    end
  end
end
