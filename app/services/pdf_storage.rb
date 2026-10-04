# PDF 本体の置き場所。PDF_STORAGE=db（既定。Neon の bytea）か r2（Cloudflare R2）。
# 読み書きは PdfBlob 経由。ここは「どちらを使うか」と R2 クライアントの入れ物だけ。
module PdfStorage
  MODES = %w[db r2].freeze

  class ChecksumMismatch < StandardError; end
  class NotConfigured < StandardError; end

  class << self
    def mode
      value = ENV.fetch("PDF_STORAGE", "db").strip.downcase
      raise ArgumentError, "PDF_STORAGE は #{MODES.join(' / ')} のどちらかにしてください（現在: #{value.inspect}）" unless MODES.include?(value)
      value
    end

    def r2? = mode == "r2"

    def r2
      @r2 ||= R2.new
    end

    # テスト用に差し替える（nil で元に戻す）
    def r2=(client)
      @r2 = client
    end
  end
end
