Rails.application.routes.draw do
  root "cases#index"

  resource :session
  resources :passwords, param: :token
  post "locale", to: "locales#update", as: :locale

  resources :cases do
    member do
      post :transition
      post :assign
      post :run_agent
    end
    resources :messages, only: :create
    post "assist/summarise", to: "assists#summarise", as: :assist_summarise
    post "assist/suggest_reply", to: "assists#suggest_reply", as: :assist_suggest_reply
  end
  resources :contacts
  resources :organisations
  resources :queues, controller: "case_queues", as: :case_queues, except: :show
  resources :categories, except: :show do
    member do
      post :toggle_auto_resolve
    end
  end
  resources :sla_policies, except: :show
  resources :macros, except: :show

  # Sales funnel (v1.2 CRM)
  resources :leads do
    member do
      post :convert
      post :mark_unqualified
    end
  end
  resources :pipelines, except: :show
  resources :deals do
    member { post :move }
  end
  resources :sequences
  resources :sequence_enrollments, only: %i[create] do
    member { post :cancel }
  end
  get "reports/sales", to: "sales_reports#index", as: :sales_report

  namespace :admin do
    resources :users do
      member do
        post :activate
        post :deactivate
      end
    end
    get "activity", to: "activity#index", as: :activity
    get "audit", to: "audit#show", as: :audit
    get "security_events", to: "security_events#index", as: :security_events
    get "settings", to: "settings#show", as: :settings
    patch "settings", to: "settings#update"
    resources :reference_docs, except: :show
    resources :api_tokens, only: %i[index create destroy]
    resources :service_accounts, except: :show do
      member do
        post :rotate_secret
      end
    end
    resources :webhook_endpoints, except: :show do
      member do
        get :deliveries
      end
    end
    resources :connectors do
      member do
        post :sync
        post :pause
        post :resume
        post :activate
        get :oauth_authorize, controller: "connector_oauth"
      end
      collection do
        get :oauth_callback, controller: "connector_oauth"
      end
    end
    resources :connector_invocations, only: %i[index show] do
      member do
        post :approve
        post :reject
      end
    end
    resources :shared_credentials, except: :show
  end

  # Inbound connector webhook ping (HMAC-signed, unauthenticated).
  post "connectors/:id/webhook", to: "connectors/webhooks#create", as: :connector_webhook

  # Public lead-capture form (v1.2 CRM) — unauthenticated.
  get "inquiry", to: "inquiries#new", as: :inquiry
  post "inquiry", to: "inquiries#create"

  namespace :portal do
    root to: "cases#new"
    resources :cases, only: %i[new create]
    get "track", to: "tracking#new", as: :track
    post "track", to: "tracking#show", as: :track_lookup
    post "track/reply", to: "tracking#reply", as: :track_reply
    resources :my_cases, only: %i[index show new create], path: "my" do
      member do
        post :reply
      end
    end
    delete "session", to: "customer_sessions#destroy", as: :customer_session
  end

  # SSO callbacks (request phase is handled by OmniAuth middleware).
  get "auth/staff_oidc/callback", to: "sso_sessions#create"
  get "auth/staff_saml/callback", to: "sso_sessions#create"
  post "auth/staff_saml/callback", to: "sso_sessions#create"
  get "auth/customer_oidc/callback", to: "portal/customer_sessions#create"
  get "auth/failure", to: "sso_failures#show"

  namespace :api do
    namespace :v1 do
      post "oauth/token", to: "oauth#token"
      get "openapi.json", to: "openapi#show"

      resources :cases, only: %i[index show create update destroy] do
        member do
          post :transition
          post :assign
        end
        resources :messages, only: %i[index create]
        post "assist/summarise", to: "assists#summarise"
        post "assist/suggest_reply", to: "assists#suggest_reply"
      end
      resources :contacts, only: %i[index show create update destroy]
      resources :organisations, only: %i[index show create update destroy]
      resources :leads, only: %i[index show create update destroy] do
        member { post :convert }
      end
      resources :pipelines, only: %i[index show create update destroy]
      resources :deals, only: %i[index show create update destroy] do
        member { post :move }
      end
      resources :sequences, only: %i[index show create update destroy]
      resources :sequence_enrollments, only: %i[index show create] do
        member { post :cancel }
      end
      resources :queues, only: %i[index show create update destroy]
      resources :categories, only: %i[index show create update destroy] do
        member do
          post :toggle_auto_resolve
        end
      end
      resources :sla_policies, only: %i[index show create update destroy]
      resources :macros, only: %i[index show create update destroy]
      resources :reference_docs, only: %i[index show create update destroy]
      resources :users, only: %i[index show create update]
      resources :api_tokens, only: %i[index create destroy]
      resources :service_accounts, only: %i[index show create update destroy] do
        member do
          post :rotate_secret
        end
      end
      resources :webhook_endpoints, only: %i[index show create update destroy] do
        member do
          get :deliveries
        end
      end
      get "audit/entries", to: "audit#entries"
      get "audit/verification", to: "audit#verification"
      get "reports/activity", to: "reports#activity"
      resource :settings, only: %i[show update]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
