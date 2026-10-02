require "csv"

module Platform
  module Commerce
    # Internal boundary only: no controller/route calls this service yet.
    # Return snapshots, never live commerce models with legacy payment methods.
    class Workspace
      class ProviderOnboardingRequired < StandardError; end
      class UnsupportedAttributes < StandardError; end

      TYPE_FIELDS = %w[id event_id name slug description price_paise capacity min_per_order max_per_order active hidden].freeze
      ORDER_FIELDS = %w[id event_id status buyer_name email total_paise created_at].freeze
      TICKET_FIELDS = %w[id event_id order_id ticket_type_id attendee_name attendee_email price_paise canceled_at].freeze
      DRAFT_FIELDS = %w[name description price_paise capacity min_per_order max_per_order].freeze

      def initialize(user:, organization_id:, event_id:)
        @policy = Policy.new(user: user, organization_id: organization_id, event_id: event_id)
      end

      def ticket_types
        @policy.with_access(:read_inventory) { |event| snapshots(TicketType.where(event_id: event.id), TYPE_FIELDS) }
      end

      def ticket_type(id)
        @policy.with_access(:read_inventory) { |event| snapshot(TicketType.where(event_id: event.id).find(id), TYPE_FIELDS) }
      end

      def create_ticket_type!(attributes)
        @policy.with_access(:manage_inventory) do |event|
          type = TicketType.create!(**draft_attributes(attributes), event_id: event.id,
            slug: "event-#{event.id}-#{SecureRandom.hex(12)}", active: false, hidden: true)
          snapshot(type, TYPE_FIELDS)
        end
      end

      def update_ticket_type!(id, attributes)
        @policy.with_access(:manage_inventory) do |event|
          type = TicketType.where(event_id: event.id).lock.find(id)
          type.update!(draft_attributes(attributes))
          snapshot(type, TYPE_FIELDS)
        end
      end

      def orders
        @policy.with_access(:read_attendees) { |event| snapshots(Order.where(event_id: event.id), ORDER_FIELDS) }
      end

      def order_by_code(code)
        @policy.with_access(:read_attendees) do |event|
          snapshot(Order.where(event_id: event.id).find_by!(code: code), ORDER_FIELDS)
        end
      end

      def tickets
        @policy.with_access(:read_attendees) { |event| snapshots(scoped_tickets(event), TICKET_FIELDS) }
      end

      def ticket(id)
        @policy.with_access(:read_attendees) { |event| snapshot(scoped_tickets(event).find(id), TICKET_FIELDS) }
      end

      def orders_csv
        @policy.with_access(:export_attendees) do |event|
          export_csv(snapshots(Order.where(event_id: event.id), ORDER_FIELDS), ORDER_FIELDS)
        end
      end

      def attendees_csv
        @policy.with_access(:export_attendees) do |event|
          export_csv(snapshots(scoped_tickets(event), TICKET_FIELDS), TICKET_FIELDS)
        end
      end

      # Explicitly deny both paid and complimentary issuance; neither may reuse
      # global Razorpay, invoice, refund, ticket PDF, or email configuration.
      def create_order!(*, **)
        @policy.with_access(:manage_inventory) do
          raise ProviderOnboardingRequired, "Event commerce requires reviewed provider, billing, and delivery onboarding"
        end
      end

      private
        def scoped_tickets(event)
          Ticket.joins(:order, :ticket_type).where(event_id: event.id)
            .where(orders: { event_id: event.id }, ticket_types: { event_id: event.id })
        end

        def draft_attributes(attributes)
          values = attributes.to_h.stringify_keys
          raise UnsupportedAttributes, "Only draft inventory fields may be changed" if (values.keys - DRAFT_FIELDS).any?

          values
        end

        def snapshot(record, fields)
          record.attributes.slice(*fields).transform_values { |value| value.deep_dup.freeze }.freeze
        end

        def snapshots(relation, fields)
          relation.order(:id).map { |record| snapshot(record, fields) }.freeze
        end

        def export_csv(rows, fields)
          CSV.generate do |csv|
            csv << fields
            rows.each { |row| csv << fields.map { |field| csv_cell(row[field]) } }
          end
        end

        def csv_cell(value)
          # CSV quoting alone does not prevent spreadsheet formula execution.
          value.is_a?(String) && value.match?(/\A[\s]*[=+@-]/) ? "'#{value}" : value
        end
    end
  end
end
