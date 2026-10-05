module PdfSplitter
  class Error < StandardError; end
  class SplitError < Error; end
  class InvalidPdf < Error; end

  # 外部コマンド（qpdf / pdftotext / pdftoppm）は CPU の優先度を最低にして動かす。
  # 同じコンテナの Puma が /up（ヘルスチェック・5秒）に返せなくなって Render に再起動されたため
  NICE = (File.executable?("/usr/bin/nice") ? %w[/usr/bin/nice -n 19] : []).freeze

  # ワーカーのプロセス全体の優先度を下げる。優先度が低いと待たされる時間も実時間に入るので、
  # Rails の Regexp.timeout（既定 1 秒・実時間）で見出し判定の正規化が落ちないよう、ワーカーでは延ばす
  WORKER_REGEXP_TIMEOUT = 30

  def self.lower_priority!
    Process.setpriority(Process::PRIO_PROCESS, 0, 19)
    Regexp.timeout = WORKER_REGEXP_TIMEOUT
  end

  def self.config = Rails.application.config.pdf_splitter
end
