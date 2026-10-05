require "csv"

module Admin
  class LoginEventsController < BaseController
    PER_PAGE = 100
    CSV_HEADER = %w[日時 メールアドレス 結果 理由 IP UA].freeze

    def index
      scope = filtered
      @total = scope.count
      @page = [ params[:page].to_i, 1 ].max
      @events = scope.recent.includes(:user).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      @per_page = PER_PAGE

      respond_to do |format|
        format.html
        format.csv do
          AuditLog.record!(:export, nil, metadata: { resource: "LoginEvent", filters: filter_params.to_h.compact_blank, rows: @total })
          send_data to_csv(scope.recent), filename: "login_events_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv", type: "text/csv; charset=utf-8"
        end
      end
    end

    private
      def filter_params
        params.permit(:q, :result, :from, :to)
      end

      def filtered
        LoginEvent.search(**filter_params.to_h.symbolize_keys)
      end

      # Excel で開いても文字化けしないよう BOM を付ける。ログインに使われた文字列は攻撃者が決められるので、数式として解釈されないようにする。
      def to_csv(scope)
        body = CSV.generate do |csv|
          csv << CSV_HEADER
          scope.find_each(order: :desc) do |e|
            csv << [ e.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M:%S"), e.email_address, e.success ? "成功" : "失敗", e.reason, e.ip_address, e.user_agent ].map { |v| CsvSafety.cell(v) }
          end
        end
        "﻿#{body}"
      end
  end
end
