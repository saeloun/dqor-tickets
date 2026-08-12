class Conversation < ApplicationRecord
  belongs_to :participant_one, class_name: "User"
  belongs_to :participant_two, class_name: "User"
  has_many :messages, -> { order(:created_at) }, dependent: :destroy

  before_validation :order_participants

  validates :participant_one_id, uniqueness: { scope: :participant_two_id }
  validate :distinct_participants

  scope :for_user, ->(user) {
    where("participant_one_id = :id OR participant_two_id = :id", id: user.id)
  }

  def self.between(user_a, user_b)
    one, two = [ user_a, user_b ].minmax_by(&:id)
    find_or_create_by!(participant_one: one, participant_two: two)
  end

  def participants
    [ participant_one, participant_two ]
  end

  def has_participant?(user)
    participant_one_id == user.id || participant_two_id == user.id
  end

  def other_participant(user)
    participant_one_id == user.id ? participant_two : participant_one
  end

  def last_read_column(user)
    participant_one_id == user.id ? :one_last_read_at : :two_last_read_at
  end

  def mark_read!(user)
    update_column(last_read_column(user), Time.current)
  end

  def unread_count_for(user)
    last_read = self[last_read_column(user)]
    scope = messages.where.not(sender_id: user.id)
    scope = scope.where("messages.created_at > ?", last_read) if last_read
    scope.count
  end

  private
    def order_participants
      return if participant_one_id.blank? || participant_two_id.blank?
      return if participant_one_id <= participant_two_id

      self.participant_one_id, self.participant_two_id = participant_two_id, participant_one_id
      self.one_last_read_at, self.two_last_read_at = two_last_read_at, one_last_read_at
    end

    def distinct_participants
      errors.add(:base, "cannot start a conversation with yourself") if participant_one_id == participant_two_id
    end
end
