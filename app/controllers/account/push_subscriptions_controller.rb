class Account::PushSubscriptionsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.assign_attributes(
      p256dh: subscription_params.dig(:keys, :p256dh),
      auth: subscription_params.dig(:keys, :auth),
      user_agent: request.user_agent
    )
    subscription.save!

    head :created
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all

    head :no_content
  end

  private
    def subscription_params
      params.expect(subscription: [ :endpoint, keys: [ :p256dh, :auth ] ])
    end
end
