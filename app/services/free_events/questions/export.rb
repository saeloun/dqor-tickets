require "csv"

module FreeEvents::Questions
  class Export
    def self.csv(**access)
      Editor.read(**access) do |event, type, _form|
        responses = FreeEvents::Response.where(event_id: event.id, ticket_type_id: type.id).includes(:form_version, :ticket).order(:id)
        CSV.generate do |csv|
          csv << %w[ticket_id form_version question_id question_label answer]
          responses.each do |response|
            response.form_version.questions.each do |q|
              value = response.answers[q["id"]]
              value = q["options"].find { |option| option["id"] == value }&.fetch("label") if q["type"] == "single_choice" && value
              csv << [ response.ticket_id, response.form_version.number, q["id"], q["label"], value ].map { |item| safe(item) }
            end
          end
        end
      end
    end

    def self.safe(value)
      value.is_a?(String) && value.match?(/\A\s*[=+@-]/) ? "'#{value}" : value
    end
  end
end
