module Api
  module V1
    module Print
      class JobsController < BaseController
        # 刷る時刻になったジョブを 1 件貸し出す（lease_until まで）。なければ 204
        def next
          job = PrintJob.lease_next_for!(station)
          job ? render(json: job_json(job)) : head(:no_content)
        end

        # 署名付き URL の期限が切れたときの取り直し
        def show
          render json: job_json(station.print_jobs.find(params[:id]))
        end

        def result
          job = station.print_jobs.find(params[:id])
          status = params[:status].to_s
          return render(json: { error: "invalid status" }, status: :unprocessable_entity) unless PrintJob::RESULT_STATUSES.key?(status)

          render json: { accepted: job.report!(status, params[:message]) }
        end
      end
    end
  end
end
