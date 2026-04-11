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
    resources :conversations, only: [] do
      get "metadata", to: "conversations/metadata#show"
      patch "metadata", to: "conversations/metadata#update"
      post "metadata/regenerate", to: "conversations/metadata#regenerate"
    end

    resources :conversation_transcripts, only: :index
    resources :conversation_diagnostics, only: [] do
      collection do
        get "show"
        get "turns"
      end
    end
    resources :conversation_turn_todo_plans, only: :index
    resources :conversation_turn_feeds, only: :index
    resources :conversation_turn_runtime_events, only: :index
    resources :conversation_supervision_sessions, only: [:create, :show] do
      member do
        post :close
      end
      resources :conversation_supervision_messages, path: "messages", only: [:index, :create]
    end
    resources :conversation_export_requests, only: [:create, :show] do
      member do
        get "download"
      end
    end
    resources :conversation_debug_export_requests, only: [:create, :show] do
      member do
        get "download"
      end
    end
    resources :conversation_bundle_import_requests, only: [:create, :show]
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
