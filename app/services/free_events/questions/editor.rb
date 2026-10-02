module FreeEvents::Questions
  class Editor
    def self.read(user:, organization_id:, event_id:, ticket_type_id:)
      Schema.require_enabled!
      FreeEvents::Access.with_manager(user: user, organization_id: organization_id, event_id: event_id) do |event|
        type = TicketType.where(event_id: event.id).find(ticket_type_id)
        form = FreeEvents::Form.find_by(ticket_type: type) || FreeEvents::Form.new(event: event, ticket_type: type)
        yield event, type, form
      end
    end

    def self.change(action:, revision:, question_id: nil, fields: {}, **access)
      read(**access) do |_event, _type, form|
        raise Invalid, { "form" => "Another organizer changed this draft. Reload and try again." } unless revision.to_s == form.lock_version.to_s
        # Revision zero belongs only to an unsaved form. First persistence must
        # invalidate every other organizer viewing the untouched category.
        form.lock_version = 1 if form.new_record?
        questions = form.draft_questions.deep_dup
        index = questions.index { |q| q["id"] == question_id }
        raise ActiveRecord::RecordNotFound if action != "add" && action != "publish" && index.nil?
        case action
        when "add", "update"
          raise Invalid, { "form" => "Choose Optional or Required" } unless %w[0 1].include?(fields["required"])
          old = index ? questions[index] : { "id" => SecureRandom.uuid, "options" => [] }
          options = if fields["type"] == "single_choice"
            fields["choices"].to_s.lines.map(&:strip).reject(&:blank?).each_with_index.map do |label, position|
              { "id" => old["options"][position]&.fetch("id") || SecureRandom.uuid, "label" => label }
            end
          else
            []
          end
          question = { "id" => old["id"], "label" => fields["label"].to_s.strip, "help" => fields["help"].to_s.strip,
            "type" => fields["type"], "required" => fields["required"] == "1", "options" => options }
          action == "add" ? questions << question : questions[index] = question
        when "remove" then questions.delete_at(index)
        when "up", "down"
          target = action == "up" ? index - 1 : index + 1
          questions[index], questions[target] = questions[target], questions[index] if target.between?(0, questions.length - 1)
        when "publish"
          Schema.validate!(questions)
          form.save! if form.new_record?
          latest = form.published_version
          return latest if latest && latest.questions == questions
          return form.versions.create!(event_id: form.event_id, ticket_type_id: form.ticket_type_id, number: (latest&.number || 0) + 1, questions: questions)
        else
          raise ActiveRecord::RecordNotFound
        end
        Schema.validate!(questions)
        form.update!(draft_questions: questions)
        form
      end
    end
  end
end
