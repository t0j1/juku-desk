# 印刷画面（tools/pdf_splitter/jobs/print）を、講師ログインと印刷専用リンクの両方で使うための URL 切り替え
module PrintRoutesHelper
  def kiosk_mode?
    controller_path == "kiosk/print"
  end

  def print_page_url_for(job)
    kiosk_mode? ? kiosk_job_url(token: params[:token], id: job) : print_tools_pdf_splitter_job_url(job)
  end

  def print_queue_path_for(job)
    kiosk_mode? ? kiosk_job_print_queue_path(token: params[:token], id: job) : print_queue_tools_pdf_splitter_job_path(job)
  end

  def output_print_path_for(job, output)
    kiosk_mode? ? kiosk_job_output_print_path(token: params[:token], job_id: job, id: output) : print_tools_pdf_splitter_job_output_path(job, output)
  end

  def output_download_path_for(job, output)
    kiosk_mode? ? kiosk_job_output_download_path(token: params[:token], job_id: job, id: output) : download_tools_pdf_splitter_job_output_path(job, output)
  end

  def print_list_path
    kiosk_mode? ? kiosk_print_path(token: params[:token]) : print_library_path
  end
end
