module Tools
  module PdfSplitter
    class OutputsController < BaseController
      before_action :set_job, :set_output

      # 印刷は inline（ブラウザで開く → 共有 → プリント）
      def print
        pdf = ::PdfSplitter::Builder.build(@output)
        AuditLog.record!(:print, @output, metadata: { job_id: @job.id, display_name: @output.display_name, pages: "#{@output.page_from}-#{@output.page_to}" })
        send_pdf pdf, filename: @output.filename, disposition: "inline"
      end

      # 保存は attachment
      def download
        pdf = ::PdfSplitter::Builder.build(@output)
        AuditLog.record!(:export, @output, metadata: { job_id: @job.id, display_name: @output.display_name })
        send_pdf pdf, filename: @output.filename, disposition: "attachment"
      end

      private
        def set_output
          @output = @job.outputs.find(params[:id])
        end
    end
  end
end
