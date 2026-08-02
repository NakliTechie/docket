Rails.application.routes.draw do
  # /up stays Rails' trivial boot check (the compose healthcheck uses it).
  # /healthz is the operator one: database, queue, storage, sweep freshness.
  get "healthz", to: "health#show"

  root "home#index"
  get "search", to: "search#index", as: :search
  resource :setup, only: %i[show update]

  resource :session
  resources :passwords, param: :token
  post "locale", to: "locales#update", as: :locale

  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/api/v1/mcp", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/oauth/authorize", to: "oauth/authorizations#new", as: :oauth_authorize
  post "/oauth/authorize", to: "oauth/authorizations#create"
  post "/oauth/register", to: "oauth/registrations#create"
  post "/oauth/token", to: "oauth/tokens#create"

  resources :notifications, only: :index do
    member { patch :read }
    collection { patch :read_all }
  end
  resources :saved_views, only: %i[create destroy]

  resources :cases do
    collection { post :bulk_update }
    member do
      post :transition
      post :assign
      post :run_agent
      post :escalate
      post :merge
      post :split
    end
    resources :messages, only: :create
    resource :presence, controller: "case_presences", only: %i[create destroy]
    post "assist/summarise", to: "assists#summarise", as: :assist_summarise
    post "assist/suggest_reply", to: "assists#suggest_reply", as: :assist_suggest_reply
  end
  # In-console knowledge-base search (staff): a turbo-frame of matching
  # articles the agent can insert into a reply.
  get "knowledge_base/search", to: "knowledge_base#search", as: :knowledge_base_search
  resources :contacts
  resources :organisations
  resources :queues, controller: "case_queues", as: :case_queues, except: :show
  resources :categories, except: :show do
    member do
      post :toggle_auto_resolve
    end
  end
  resources :sla_policies, except: :show
  resources :entitlements, except: :show
  resources :business_calendars, except: :show
  resources :macros, except: :show
  resources :routing_rules, except: :show do
    member do
      patch :move
    end
  end
  resources :lead_routing_rules, except: :show do
    member do
      patch :move
    end
  end
  resources :escalation_rules, except: :show do
    member do
      patch :move
    end
  end
  resources :activities, except: :show do
    member do
      patch :complete
    end
  end
  resources :custom_fields, controller: "custom_field_definitions", except: %i[show destroy]
  # Work module (WM). Items are reachable by their own id at /work_items/:id so
  # a KEY-123 link survives a project rename; creation and listing stay nested.
  resources :projects do
    member do
      post :archive
    end
    resource :board, only: :show
    resources :work_items, only: %i[index new create] do
      collection { post :bulk_update }
    end
    resources :sprints, except: :show do
      member do
        post :start
        post :close
      end
    end
  end
  resources :work_items, only: %i[show edit update destroy] do
    member do
      post :transition
      post :watch
    end
    resources :work_comments, only: :create
    resources :relations, controller: "work_item_relations", only: :create
  end
  resources :work_item_relations, only: :destroy
  resources :work_comments, only: %i[update destroy]
  resources :project_templates, except: :show

  resources :approval_processes, except: :show

  # Sales funnel (v1.2 CRM)
  resources :leads do
    member do
      post :convert
      post :mark_unqualified
      post :merge
    end
  end
  resources :lead_capture_forms, except: :show
  resources :pipelines, except: :show
  resources :deals do
    member do
      post :move
      post :onboard
      post :engage
    end
    resources :line_items, controller: "deal_line_items", only: :create
    resources :competitor_links, controller: "deal_competitors", only: :create
    resources :contact_roles, controller: "deal_contact_roles", only: :create
  end
  resources :crm_messages, only: :create
  resources :deal_line_items, only: %i[update destroy]
  resources :deal_competitors, only: %i[update destroy]
  resources :deal_contact_roles, only: %i[update destroy]
  resources :products, except: :show
  resources :price_books, except: :show
  resources :competitors, except: :show
  resources :campaigns
  resources :sequences
  resources :sequence_enrollments, only: %i[create] do
    member { post :cancel }
  end
  get "reports/sales", to: "sales_reports#index", as: :sales_report
  get "reports/custom_fields", to: "custom_field_reports#index", as: :custom_field_report
  get "reports/csat", to: "csat_reports#index", as: :csat_report
  get "dashboard", to: "dashboards#index", as: :dashboard
  post "decisions/run", to: "decisions#run", as: :run_decisions
  post "decisions/:id/approve", to: "decisions#approve", as: :approve_decision
  post "decisions/:id/reject", to: "decisions#reject", as: :reject_decision

  namespace :admin do
    resources :teams, except: :show
    resources :users do
      member do
        post :activate
        post :deactivate
      end
    end
    get "roles", to: "roles#index", as: :roles
    resources :tenants, only: %i[index new create] do
      member do
        post :suspend
        post :activate
        get :entitlements
        patch :entitlements, action: :update_entitlements
      end
    end
    resources :decision_appeals, only: %i[index create] do
      member do
        post :overturn
        post :deny
      end
    end
    resources :approval_requests, only: %i[index] do
      member do
        post :approve
        post :reject
      end
    end
    get "activity", to: "activity#index", as: :activity
    get "audit", to: "audit#show", as: :audit
    get "security_events", to: "security_events#index", as: :security_events
    get "settings", to: "settings#show", as: :settings
    patch "settings", to: "settings#update"
    resource :lead_scorecard, only: %i[show update]
    resources :reference_docs do
      member do
        post :toggle_published
        post :retire
      end
    end
    resources :knowledge_categories, except: :show
    resources :api_tokens, only: %i[index create destroy]
    resources :service_accounts, except: :show do
      member do
        post :rotate_secret
      end
    end
    resources :oauth_clients, only: %i[index destroy]
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

  # Inbound connector webhook ping (HMAC-signed, unauthenticated). GET is the
  # platform webhook-URL verification handshake (WhatsApp Cloud).
  post "connectors/:id/webhook", to: "connectors/webhooks#create", as: :connector_webhook
  get  "connectors/:id/webhook", to: "connectors/webhooks#verify", as: :connector_webhook_verify

  # Public lead-capture form (v1.2 CRM) — unauthenticated.
  get "inquiry", to: "inquiries#new", as: :inquiry
  post "inquiry", to: "inquiries#create"
  get "inquiry/:slug", to: "inquiries#new", as: :lead_capture
  post "inquiry/:slug", to: "inquiries#create"

  namespace :portal do
    root to: "cases#new"
    resource :live_chat, only: %i[new create show] do
      post :message
      delete :end_chat
    end
    resources :kb, only: %i[index show], controller: "knowledge_base", param: :slug do
      member { post :rate }
    end
    resources :cases, only: %i[new create]
    get "track", to: "tracking#new", as: :track
    post "track", to: "tracking#show", as: :track_lookup
    post "track/reply", to: "tracking#reply", as: :track_reply
    resources :my_cases, only: %i[index show new create], path: "my" do
      member do
        post :reply
      end
    end
    resources :decisions, only: :index do
      member { post :appeal }
    end
    delete "session", to: "customer_sessions#destroy", as: :customer_session
  end

  # SSO callbacks (request phase is handled by OmniAuth middleware).
  get "auth/staff_oidc/callback", to: "sso_sessions#create"
  get "auth/staff_saml/callback", to: "sso_sessions#create"
  post "auth/staff_saml/callback", to: "sso_sessions#create"
  get "auth/customer_oidc/callback", to: "portal/customer_sessions#create"
  get "auth/failure", to: "sso_failures#show"

  get "sequence_unsubscribe/:token", to: "sequence_unsubscribes#show",
      as: :sequence_unsubscribe
  post "sequence_unsubscribe/:token", to: "sequence_unsubscribes#create"
  get "sequence_tracking/:token/open.gif", to: "sequence_tracking#open",
      as: :sequence_tracking_open
  get "sequence_tracking/:token/click", to: "sequence_tracking#click",
      as: :sequence_tracking_click
  get "survey/csat/:token", to: "csat_surveys#show", as: :csat_survey
  post "survey/csat/:token", to: "csat_surveys#create"

  namespace :api do
    namespace :v1 do
      post "oauth/token", to: "/oauth/tokens#create"
      get "openapi.json", to: "openapi#show"
      # MCP server face (PG5): JSON-RPC over the api/v1 surface.
      post "mcp", to: "mcp#handle"

      resources :cases, only: %i[index show create update destroy] do
        member do
          post :transition
          post :assign
          post :merge
          post :split
        end
        resources :messages, only: %i[index create]
        post "assist/summarise", to: "assists#summarise"
        post "assist/suggest_reply", to: "assists#suggest_reply"
      end
      resources :contacts, only: %i[index show create update destroy]
      resources :organisations, only: %i[index show create update destroy]
      resources :leads, only: %i[index show create update destroy] do
        member do
          post :convert
          post :merge
        end
      end
      resources :lead_capture_forms, only: %i[index show create update destroy]
      resources :pipelines, only: %i[index show create update destroy]
      resources :deals, only: %i[index show create update destroy] do
        member do
          post :move
          post :onboard
          post :engage
        end
        resources :line_items, controller: "deal_line_items", only: :create
        resources :competitor_links, controller: "deal_competitors", only: :create
        resources :contact_roles, controller: "deal_contact_roles", only: :create
      end
      resources :deal_line_items, only: %i[update destroy]
      resources :deal_competitors, only: %i[update destroy]
      resources :deal_contact_roles, only: %i[update destroy]
      resources :products, only: %i[index show create update destroy]
      resources :competitors, only: %i[index show create update destroy]
      resources :campaigns, only: %i[index show create update destroy]
      resources :activities, only: %i[index show create update destroy] do
        member { post :complete }
      end
      resources :crm_messages, only: %i[index create]
      resources :sequences, only: %i[index show create update destroy]
      resources :sequence_enrollments, only: %i[index show create] do
        member { post :cancel }
      end
      # Work module (WM5)
      resources :projects, only: %i[index show create update destroy]
      resources :project_templates, only: %i[index show create update destroy]
      get "projects/:project_id/sprint_report", to: "sprints#report"
      resources :work_items, only: %i[index show create update destroy] do
        member { post :transition }
        resources :work_comments, only: %i[index create], controller: "work_comments"
        resources :relations, only: :create, controller: "work_item_relations"
      end
      resources :work_item_relations, only: :destroy
      resources :work_comments, only: %i[update destroy]
      resources :sprints, only: %i[index show create update] do
        member { post :close }
      end

      resources :queues, only: %i[index show create update destroy]
      resources :categories, only: %i[index show create update destroy] do
        member do
          post :toggle_auto_resolve
        end
      end
      resources :sla_policies, only: %i[index show create update destroy]
      resources :business_calendars, only: %i[index show create update destroy]
      resources :custom_fields, controller: "custom_fields", only: %i[index show create update]
      resources :macros, only: %i[index show create update destroy]
      resources :reference_docs, only: %i[index show create update destroy] do
        member do
          get :versions
          post :publish
          post :retire
        end
      end
      resources :knowledge_categories, only: %i[index show create update destroy]
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
      resources :decisions, only: %i[index show] do
        collection { post :run }
        member do
          post :approve
          post :reject
        end
      end
      get "audit/entries", to: "audit#entries"
      get "audit/verification", to: "audit#verification"
      get "reports/activity", to: "reports#activity"
      get "reports/sales", to: "reports#sales"
      get "reports/custom_fields", to: "custom_field_reports#index"
      get "reports/csat", to: "reports#csat"
      resource :settings, only: %i[show update]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
