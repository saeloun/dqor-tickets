class Avo::Actions::ResendConfirmation < Avo::BaseAction
  self.name = "Resend confirmation"
  self.confirmation = false

  def handle(query:, **)
    query.each(&:resend_confirmation!)
    succeed "Confirmation queued"
  end
end
