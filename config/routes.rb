Rails.application.routes.draw do
  root "tickets#index"

  mount_avo at: "/avo"

  resource :checkin, only: %i[show create]

  resource :checkout_preview, only: :create
  resources :orders, param: :code, only: [ :create, :show ]
  post "payments/callback", to: "payments#callback", as: :payment_callback

  namespace :webhooks do
    resource :razorpay, only: :create, controller: "razorpay"
  end

  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

if defined? ::Avo
  Avo::Engine.routes.draw do
    get "dashboard", to: "tools#dashboard", as: :dashboard
  end
end
