Rails.application.routes.draw do
  root "pages#home"
  get "about" => "pages#about"
  get "contact" => "pages#contact"

  # Host accounts
  resource :registration, only: %i[new create]
  resource :session
  resources :passwords, param: :token

  # Host dashboard
  resources :events do
    member do
      post :publish
      get :cancellation
      post :cancel
      post :duplicate
      get :preview
      post :regenerate_share_link
    end

    resource :design, only: %i[edit update], controller: "event_designs"
    resources :guests, except: %i[index show] do
      member do
        patch :rsvp
        post :resend
      end
      collection do
        get :export
        post :bulk
      end
    end
    resources :guest_imports, only: %i[new create show destroy] do
      member { patch :confirm }
      collection { get :template }
    end
    resource :invitation_send, only: :create
    resources :messages, only: %i[index new create show destroy] do
      member { post :retry_failed }
      collection { get :audience_count }
    end
    resources :questions, except: %i[index show] do
      member { patch :move }
    end
  end

  # Guests: no account needed, access is via the secret token in the personal link.
  scope "i/:token", constraints: { token: /[A-Za-z0-9_-]{40}/ }, controller: "guest_invitations", as: :guest do
    get "/", action: :show, as: :invitation
    patch "rsvp", action: :rsvp, as: :rsvp
    get "calendar.ics", action: :calendar, as: :calendar, format: false
    post "unsubscribe", action: :unsubscribe, as: :unsubscribe
  end

  # Public share link: the invitation without personal data; optional open RSVP.
  scope "e/:share_token", constraints: { share_token: /[A-Za-z0-9]{24}/ }, controller: "public_events", as: :public_event do
    get "/", action: :show, as: ""
    post "rsvp", action: :rsvp, as: :rsvp
    get "calendar.ics", action: :calendar, as: :calendar, format: false
  end

  # Provider callbacks (authenticated by shared token / Twilio signature).
  namespace :webhooks do
    post "email" => "email#create"
    post "twilio/status" => "twilio#status"
    post "twilio/inbound" => "twilio#inbound"
  end

  # Local development outbox: captured emails and SMS.
  if Rails.application.config.x.outbox_enabled
    namespace :dev do
      resources :outbox, only: %i[index show], controller: "outbox" do
        member { get :html }
        collection { delete :clear }
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
