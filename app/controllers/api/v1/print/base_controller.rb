module Api
  module V1
    module Print
      # 教室PCの自動印刷エージェント向け API。ログインではなく、ステーションごとの Bearer トークンで認証する。
      class BaseController < ActionController::API
        before_action :authenticate_station!

        private
          attr_reader :station

          def authenticate_station!
            token = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
            @station = PrintStation.authenticate(token)
            render json: { error: "unauthorized" }, status: :unauthorized unless @station
          end

          def job_json(job) = { job: job.as_agent_json(base_url: request.base_url) }
      end
    end
  end
end
