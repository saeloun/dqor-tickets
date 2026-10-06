module EventWebsitesHelper
  def website_asset_path(slot)
    id = @configuration.to_h.fetch("assets")[slot]
    return unless id
    if @website_preview
      asset_organizer_organization_event_website_path(@event.organization, @event, asset_id: id)
    else
      event_website_asset_path(@event.organization.slug, @event.slug, asset_id: id)
    end
  end

  def website_section_label(section)
    section == "programme" ? "Programme" : section.humanize
  end
end
