module Api
  module V1
    module Print
      class HeartbeatsController < BaseController
        # 応答の server_time で、エージェントは自分の時計とのずれを補正する。
        # 自動更新（latest_version / download_url / sha256）は、3 つとも設定されているときだけ返す。
        def create
          station.seen!(params[:agent_version])
          PrintJob.sweep!
          render json: { server_time: Time.current.utc.iso8601 }.merge(update_info)
        end

        private
          def update_info
            info = { latest_version: ENV["PRINT_AGENT_LATEST_VERSION"], download_url: ENV["PRINT_AGENT_DOWNLOAD_URL"], sha256: ENV["PRINT_AGENT_SHA256"] }
            info.values.all?(&:present?) ? info : {}
          end
      end
    end
  end
end
