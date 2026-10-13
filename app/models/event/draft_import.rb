class Event::DraftImport
  Result = Data.define(:event, :status)

  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @event = event
  end

  def call
    existing = existing_event
    return duplicate_result(existing) if existing

    return Result.new(event: @event, status: :created) if @event.save

    existing = existing_event
    existing ? duplicate_result(existing) : Result.new(event: @event, status: :invalid)
  rescue ActiveRecord::RecordNotUnique
    existing = existing_event
    return duplicate_result(existing) if existing

    @event.errors.add(:base, "An event with this URL name already exists. Choose another URL name.")
    Result.new(event: @event, status: :invalid)
  end

  private
    def existing_event
      @event.organization.events.find_by(source_url: @event.source_url) if @event.source_url.present?
    end

    def duplicate_result(existing)
      if [ existing.starts_at, existing.ends_at, existing.timezone ] == [ @event.starts_at, @event.ends_at, @event.timezone ]
        Result.new(event: existing, status: :existing)
      else
        @event.errors.add(:source_url, "already belongs to an event with different dates or timezone. Review the existing event before changing it.")
        Result.new(event: @event, status: :conflict)
      end
    end
end
