Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
  mount ActionCable.server => "/cable"

  namespace :agent_api do
    resources :registrations, only: :create
    resources :heartbeats, only: :create
    resource :health, only: :show, controller: :health
    resource :capabilities, only: [:show, :create], controller: :capabilities
    resources :conversation_transcripts, only: :index
    resources :conversation_variables, only: [] do
      collection do
        get "get"
        post "mget"
        get "exists"
        get "list_keys"
        get "resolve"
        post "set"
        post "delete"
        post "promote"
      end
    end
    resources :workspace_variables, only: :index do
      collection do
        get "get", action: :show_value
        post "mget", action: :bulk_show
        post "write"
      end
    end
    resources :human_interactions, only: :create
    resources :tool_invocations, only: :create
    post "control/poll", to: "control#poll"
    post "control/report", to: "control#report"
  end

  namespace :execution_runtime_api do
    resources :registrations, only: :create
    resource :health, only: :show, controller: :health
    resource :capabilities, only: [:show, :create], controller: :capabilities
    resources :command_runs, only: :create do
      post :activate, on: :member
    end
    resources :process_runs, only: :create
    resources :attachments, only: [] do
      collection do
        post "request", action: :create
      end
    end
    post "control/poll", to: "control#poll"
    post "control/report", to: "control#report"
  end

  namespace :app_api do
    namespace :admin do
      resource :installation, only: :show
      resources :agents, only: :index
      resources :execution_runtimes, only: :index
      resources :onboarding_sessions, only: [:index, :create]
      resources :audit_entries, only: :index
      resources :llm_providers, only: [:index, :show, :update], param: :provider do
        member do
          patch :credential, to: "llm_providers/credentials#update"
          put :credential, to: "llm_providers/credentials#update"
          patch :policy, to: "llm_providers/policies#update"
          put :policy, to: "llm_providers/policies#update"
          patch :entitlements, to: "llm_providers/entitlements#update"
          put :entitlements, to: "llm_providers/entitlements#update"
          post :test_connection, to: "llm_providers/connection_tests#create"
        end
      end

      namespace :llm_providers do
        namespace :codex_subscription do
          resource :authorization, only: [:show, :create, :destroy], controller: :authorizations do
            get :callback
          end
        end
      end
    end

    resources :agents, only: :index do
      resource :home, only: :show, controller: "agents/homes"
      resources :workspaces, only: :index, controller: "agents/workspaces"
    end

    resources :conversations, only: :create do
      resource :metadata, only: [:show, :update], controller: "conversations/metadata" do
        post :regenerate
      end
      resources :messages, only: :create, controller: "conversations/messages"
      resource :transcript, only: :show, controller: "conversations/transcript"
      resource :diagnostics, only: :show, controller: "conversations/diagnostics" do
        get :turns
      end
      resource :todo_plan, only: :show, controller: "conversations/todo_plans"
      resource :feed, only: :show, controller: "conversations/feeds"
      resources :export_requests, only: [:create, :show], controller: "conversations/export_requests" do
        get :download, on: :member
      end
      resources :debug_export_requests, only: [:create, :show], controller: "conversations/debug_export_requests" do
        get :download, on: :member
      end
      resources :supervision_sessions, only: [:create, :show], controller: "conversations/supervision/sessions" do
        post :close, on: :member
        resources :messages, only: [:index, :create], controller: "conversations/supervision/messages"
      end
      resources :turns, only: [] do
        resources :runtime_events, only: :index, controller: "conversations/turns/runtime_events"
      end
    end

    resources :workspaces, only: [] do
      resource :policy, only: [:show, :update], controller: "workspaces/policies"
      resources :conversation_bundle_import_requests, only: [:create, :show], controller: "workspaces/conversation_bundle_import_requests"
    end
  end

  if Rails.env.development? || Rails.env.test?
    namespace :mock_llm do
      namespace :v1 do
        post "chat/completions", to: "chat_completions#create"
        get "models", to: "models#index"
      end
    end
  end
end
