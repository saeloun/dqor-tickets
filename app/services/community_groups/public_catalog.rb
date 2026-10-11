module CommunityGroups
  class PublicCatalog
    Page = Data.define(:records, :page, :total)

    def self.page(scope, value)
      page = page_number(value)
      Page.new(records: scope.limit(24).offset((page - 1) * 24), page: page, total: scope.count)
    end

    def self.page_number(value)
      return 1 unless value.is_a?(String) && value.match?(/\A[0-9]+\z/)
      value = value.sub(/\A0+/, "")
      return 1_000 if value.length > 4

      [ [ value.to_i, 1 ].max, 1_000 ].min
    end

    def self.group(organization_slug:, group_slug:)
      CommunityGroup.published.joins(:organization).includes(:organization).find_by!(slug: group_slug, organizations: { slug: organization_slug })
    end

    def self.events(group, upcoming:)
      scope = group.events.published.includes(:organization).where(organization_id: group.organization_id)
      upcoming ? scope.where("ends_at >= ?", Time.current).order(:starts_at, :id) : scope.where("ends_at < ?", Time.current).order(starts_at: :desc, id: :desc)
    end

    def self.serialize(group)
      group.attributes.slice("name", "slug", "tagline", "description", "city", "country_code", "timezone").merge(
        "id" => "community-#{group.id}", "ownership" => "tenant_owned_community",
        "organizer" => { "name" => group.organization.name, "slug" => group.organization.slug }
      )
    end
  end
end
