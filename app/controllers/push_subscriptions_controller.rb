class PushSubscriptionsController < ApplicationController
  allow_unauthenticated_access

  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.assign_attributes(
      p256dh_key: subscription_params.dig(:keys, :p256dh),
      auth_key: subscription_params.dig(:keys, :auth),
      user_agent: request.user_agent,
      email: session[:ticket_access_email]
    )
    subscription.save!

    head :created
  end

  private
    def subscription_params
      params.expect(subscription: [ :endpoint, keys: [ :p256dh, :auth ] ])
    end
end
