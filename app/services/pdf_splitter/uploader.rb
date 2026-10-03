module PdfSplitter
  # アップロードの検証と保存。サイズ・ページ数・1日の件数・MIME と先頭バイトを確認する
  class Uploader
    Result = Struct.new(:job, :error, keyword_init: true)

    def initialize(user)
      @user = user
      @limits = PdfSplitter.config[:limits]
      @retention = PdfSplitter.config[:retention]
    end

    def call(file, password: nil)
      return fail!("PDFファイルを選んでください。") if file.blank?
      return fail!("PDFファイルのみアップロードできます。") unless file.content_type == "application/pdf"
      return fail!("ファイルが大きすぎます（上限 #{max_mb}MB）。") if file.size > max_mb.megabytes
      if @user.pdf_split_jobs.created_today.count >= @limits[:max_jobs_per_day].to_i
        return fail!("本日のアップロード上限（#{@limits[:max_jobs_per_day]}件）に達しました。")
      end

      data = file.read.b
      return fail!("PDFファイルではありません。") unless data.start_with?("%PDF-")

      data = Splitter.decrypt_to_string(data, password:) if password.present?
      pages = Splitter.page_count_of(data)
      return fail!("ページ数が多すぎます（上限 #{@limits[:max_pages]}ページ）。") if pages > @limits[:max_pages].to_i
      return fail!("ページがありません。") if pages < 1

      job = PdfSplitJob.transaction do
        j = @user.pdf_split_jobs.create!(original_filename: File.basename(file.original_filename.to_s).presence || "upload.pdf",
                                         page_count: pages)
        j.pdf_blobs.create!(kind: "original", data:, byte_size: data.bytesize, expires_at: @retention[:days].to_i.days.from_now)
        j
      end
      spreads = Splitter.with_tempfile(data) { |path| Spread.landscape_pages(path, pages) }
      job.update!(spread_state: :pending, spread_pages: spreads) if spreads.any?
      Result.new(job:)
    rescue InvalidPdf
      fail!(password.present? ? "PDFを開けませんでした。パスワードを確認してください。" : "PDFを開けませんでした。パスワード付きの場合は入力してください。")
    end

    private
      def max_mb = [ @limits[:max_file_mb].to_i, @retention[:max_original_mb].to_i ].min
      def fail!(message) = Result.new(error: message)
  end
end
