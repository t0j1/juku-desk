module Api
  module V1
    module Print
      # PDF_STORAGE=db のときの PDF の配信。R2 の署名付き URL の代わりに、10 分で切れる署名つきの URL にする（ヘッダーなしで取れる）。
      class FilesController < ActionController::API
        def show
          job = PrintJob.find_signed(params[:signed_id], purpose: :print_file)
          return head :not_found unless job&.pdf_data

          send_data job.pdf_data, type: "application/pdf", disposition: "attachment", filename: "#{job.id}.pdf"
        end
      end
    end
  end
end
