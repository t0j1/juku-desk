Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resources :invitations, param: :token, only: %i[ edit update ]
  resources :passwords, param: :token, only: %i[ new create edit update ]

  resources :announcements, only: [] do
    post :read, on: :member
  end
  resource :impersonation, only: :destroy
  resource :two_factor, only: %i[ show new create destroy ]
  resource :two_factor_challenge, only: %i[ new create ]

  resources :user_sessions, path: "account/sessions", only: %i[ index destroy ] do
    delete :destroy_others, on: :collection
  end

  namespace :admin do
    resources :users, only: %i[ index new create update ] do
      post :unlock, on: :member
      post :suspend, on: :member
      post :activate, on: :member
      post :resend_invitation, on: :member
      post :reset_two_factor, on: :member
      resource :impersonation, only: %i[ new create ]
    end
    resources :login_events, only: :index
    resources :mail_templates, only: %i[ index edit update ], param: :key do
      post :preview, on: :member
      post :reset, on: :member
    end
    resource :user_import, only: %i[ new create ] do
      post :confirm
    end
    resource :user_suspension, only: %i[ new create ] do
      post :confirm
    end
    resources :announcements, except: :show
  end

  resources :students do
    resources :student_weekdays, only: %i[ create destroy ]
  end

  resources :wordbooks, only: %i[ index create ]

  # マーキング検出：赤枠で囲んだ教材画像の取り込みと、Gemini が作った問題のレビュー
  # （/marking/:id より先に書く。"questions" を uploads#show の id として拾わせない）
  resources :questions, path: "marking/questions", only: %i[ index edit update ] do
    member do
      post :approve
      post :unapprove
    end
  end
  resources :marking_tests, path: "marking/tests", only: %i[ index new create show ] do
    get :print, on: :member
  end
  resources :uploads, path: "marking", only: %i[ index new create show ] do
    get :image, on: :member
    post :extract, on: :member
  end
  resources :crop_regions, path: "marking/regions", only: [] do
    get :image, on: :member
  end
  resources :quizzes, only: %i[ new create ]

  namespace :tools do
    namespace :pdf_splitter do
      resources :jobs, only: %i[ index show create destroy ] do
        member do
          post  :analyze
          post  :split
          match :update_boundaries, via: %i[ patch post ]
          patch :update_names
          get   :print
          get   :print_bundle
          get   :print_queue
          get   :download_zip
          get   :thumbnail
        end
        resources :outputs, only: [] do
          member do
            get :print
            get :download
          end
        end
      end
    end
  end

  # schedule-web を juku-desk のレイアウト（サイドバー）の中に iframe で埋め込む（SCHEDULE_WEB_URL が必要）
  get "schedule" => "schedule#index", as: :schedule
  get "schedule/admin" => "schedule#admin", as: :schedule_admin
  get "schedule/pickup" => "schedule#pickup", as: :schedule_pickup
  post "schedule/token" => "schedule_tokens#create", as: :schedule_token

  # 印刷（講師ログイン）
  get  "print" => "print_library#index", as: :print_library
  post "print/reissue" => "print_library#reissue", as: :reissue_print_link

  # 印刷専用リンク（共用 iPad・ログイン不要）
  scope "print/:token", as: :kiosk, token: /[A-Za-z0-9]{20,}/ do
    get "" => "kiosk/print#index", as: :print
    get "jobs/:id" => "kiosk/print#show", as: :job
    get "jobs/:id/print_queue" => "kiosk/print#print_queue", as: :job_print_queue
    get "jobs/:id/print_bundle" => "kiosk/print#print_bundle", as: :job_print_bundle
    get "jobs/:job_id/outputs/:id/print" => "kiosk/print#output_print", as: :job_output_print
    get "jobs/:job_id/outputs/:id/download" => "kiosk/print#output_download", as: :job_output_download
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Phase 2 で lessons#index に変更する
  root "home#index"
end
