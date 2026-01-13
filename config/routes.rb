Rails.application.routes.draw do
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
  post "/graphql", to: "graphql#execute"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # API REST v1 - Apenas Autenticação
  namespace :api do
    namespace :v1 do
      # Rotas de autenticação (REST)
      post 'auth/login', to: 'auth#login'      # Login (retorna token JWT)
      get 'auth/me', to: 'auth#me'             # Perfil do usuário autenticado
      post 'auth/logout', to: 'auth#logout'    # Logout
      
      # CRUD de usuários agora é feito via GraphQL
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
