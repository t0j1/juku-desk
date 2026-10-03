# 印刷専用リンク（/print/<token>）。ログイン不要で、分割済みファイルの一覧と印刷画面だけを開ける
module Kiosk
  class PrintController < ApplicationController
    allow_unauthenticated_access
    before_action :require_print_link
    before_action :set_job, except: :index
    layout "kiosk"

    rescue_from ActiveRecord::RecordNotFound, with: -> { redirect_to kiosk_print_path(token: params[:token]) }
    rescue_from ::PdfSplitter::Error, with: ->(e) { redirect_to kiosk_job_path(token: params[:token], id: @job), alert: e.message }

    def index
      @query = params[:q].to_s
      @jobs = PdfSplitJob.printable(@query).limit(100)
    end

    def show
      @outputs = @job.outputs.to_a
      @rounds = @outputs.select(&:round_label).group_by(&:round_label)
      @paper = @job.spread_split? ? "b4" : "b5"
      render "tools/pdf_splitter/jobs/print"
    end

    def print_queue
      queue = ::PdfSplitter::PrintQueue.new(@job, params[:items], pad_even: params[:pad_even] == "1", paper: params[:paper], include_neighbor: params[:include_neighbor] == "1")
      return redirect_to(kiosk_job_path(token: params[:token], id: @job), alert: queue.errors.join(" ")) unless queue.valid?
      audit(@job, queue: params[:items], pad_even: params[:pad_even] == "1")
      send_pdf queue.to_pdf, filename: queue.filename, disposition: "inline"
    end

    def print_bundle
      outputs = @job.outputs.where(round_label: params[:round]).to_a
      return redirect_to(kiosk_job_path(token: params[:token], id: @job), alert: "対象のファイルがありません。") if outputs.empty?
      audit(@job, bundle: params[:round], outputs: outputs.map(&:display_name))
      send_pdf ::PdfSplitter::PrintOptimizer.bundle(outputs), filename: "#{params[:round]}_まとめ.pdf", disposition: "inline"
    end

    def output_print
      output = @job.outputs.find(params[:id])
      audit(output, display_name: output.display_name, pages: "#{output.page_from}-#{output.page_to}")
      send_pdf ::PdfSplitter::Builder.build(output), filename: output.filename, disposition: "inline"
    end

    def output_download
      output = @job.outputs.find(params[:id])
      AuditLog.record!(:export, output, user: nil, metadata: { job_id: @job.id, display_name: output.display_name, via: "print_link" })
      send_pdf ::PdfSplitter::Builder.build(output), filename: output.filename, disposition: "attachment"
    end

    private
      def require_print_link
        @print_link = PrintLink.find_active(params[:token])
        redirect_to new_session_path unless @print_link
      end

      def set_job
        @job = PdfSplitJob.done.find(params[:job_id] || params[:id])
      end

      def audit(record, **metadata)
        AuditLog.record!(:print, record, user: nil, metadata: metadata.merge(job_id: @job.id, via: "print_link"))
      end

      def send_pdf(data, filename:, disposition:)
        send_data data, filename:, type: "application/pdf", disposition:
      end
  end
end
