module Tools
  module PdfSplitter
    class OutputsController < BaseController
      before_action :set_job, :set_output

      # 印刷は inline（ブラウザで開く → 共有 → プリント）
      def print
        AuditLog.record!(:print, @output, metadata: { job_id: @job.id, display_name: @output.display_name, pages: "#{@output.page_from}-#{@output.page_to}" })
        send_output_pdf @output, disposition: "inline"
      end

      # 保存は attachment
      def download
        AuditLog.record!(:export, @output, metadata: { job_id: @job.id, display_name: @output.display_name })
        send_output_pdf @output, disposition: "attachment"
      end

      private
        def set_output
          @output = @job.outputs.find(params[:id])
        end
    end
  end
end
