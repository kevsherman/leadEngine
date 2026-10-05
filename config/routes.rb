Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :conversations, only: %i[index show]
  resources :email_drafts, only: :update do
    member do
      get :review
      post :approve
      post :send_reply
      post :reconcile
      post :new_reply
    end
  end
  resource :gmail_connection, only: %i[show update] do
    post :connect
    post :sync
    post :enable_sending
    post :disable_sending
    post :disconnect
  end
  get "gmail/callback", to: "gmail_connections#callback", as: :gmail_callback
  resources :gmail_review_items, only: :update
  get "up" => "rails/health#show", as: :rails_health_check
  root "conversations#index"
end
