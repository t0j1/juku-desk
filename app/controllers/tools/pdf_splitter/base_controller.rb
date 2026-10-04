module Tools
  module PdfSplitter
    class BaseController < ApplicationController
      include PdfStreaming
      rescue_from ::PdfSplitter::Error, with: :pdf_error

      private
        def set_job
          @job = current_user.pdf_split_jobs.find(params[:job_id] || params[:id])
        end

        def pdf_error(error)
          redirect_to(@job ? tools_pdf_splitter_job_path(@job) : tools_pdf_splitter_jobs_path, alert: error.message)
        end
    end
  end
end
