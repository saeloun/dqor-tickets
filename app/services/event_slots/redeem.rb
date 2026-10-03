module EventSlots
  class Redeem
    class Rejected < StandardError; end

    def self.call(slot:, ticket:, operator:, request_key:)
      raise Rejected, "Staff permission required" unless operator&.admin? || operator&.desk?
      raise Rejected, "Ticket not found" unless ticket
      raise Rejected, "Request key required" unless request_key.to_s.match?(/\A[a-zA-Z0-9-]{16,100}\z/)

      slot.with_lock do
        ticket.order.with_lock do
          ticket.with_lock do
            prior = slot.redemptions.find_by(request_key:)
            if prior
              raise Rejected, "Request key already used" unless prior.ticket_id == ticket.id
              raise Rejected, "This redemption was corrected; start a new scan" if prior.voided_at?
              return prior
            end
            now = Time.current
            day = now.in_time_zone("Asia/Kolkata").to_date
            raise Rejected, "Slot is closed or draft" unless slot.active? && now >= slot.starts_at && now < slot.ends_at
            raise Rejected, "Ticket is not confirmed" unless ticket.order.paid? && !ticket.canceled_at?
            raise Rejected, "Ticket is not valid on this day" unless Ticket::EVENT_DATES.include?(day) && ticket.ticket_type.valid_on?(day)
            raise Rejected, "Ticket has no entitlement for this purpose" unless slot.ticket_type_ids.include?(ticket.ticket_type_id)
            raise Rejected, "Already redeemed for this purpose" if slot.redemptions.current.where(ticket:).count >= slot.redemption_limit
            raise Rejected, "Slot capacity reached" if slot.capacity && slot.redemptions.current.count >= slot.capacity
            slot.redemptions.create!(ticket:, admin_user: operator, request_key:, redeemed_at: now)
          end
        end
      end
    end

    def self.correct!(redemption:, operator:, reason:)
      raise Rejected, "Organizer permission required" unless operator&.admin?
      raise Rejected, "Correction reason required" if reason.to_s.strip.empty?
      redemption.event_slot.with_lock do
        redemption.with_lock do
          raise Rejected, "Already corrected" if redemption.voided_at?
          redemption.update!(voided_at: Time.current, voided_by: operator, void_reason: reason.to_s.strip)
        end
      end
    end
  end
end
