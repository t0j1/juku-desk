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

      # アップロードは一時ファイルに書いてパスで扱う（全体を String にしない）。R2 ならそのままストリーミングで送る
      job = Dir.mktmpdir do |dir|
        path = File.join(dir, "upload.pdf")
        File.open(path, "wb") { |f| IO.copy_stream(file, f) }
        return fail!("PDFファイルではありません。") unless File.binread(path, 5) == "%PDF-"

        if password.present?
          decrypted = File.join(dir, "decrypted.pdf")
          Splitter.decrypt(path, decrypted, password:)
          path = decrypted
        end
        pages = Splitter.page_count(path)
        return fail!("ページ数が多すぎます（上限 #{@limits[:max_pages]}ページ）。") if pages > @limits[:max_pages].to_i
        return fail!("ページがありません。") if pages < 1

        PdfSplitJob.transaction do
          j = @user.pdf_split_jobs.create!(original_filename: File.basename(file.original_filename.to_s).presence || "upload.pdf",
                                           page_count: pages)
          PdfBlob.store!(kind: "original", pdf_split_job: j, path:, expires_at: @retention[:days].to_i.days.from_now)
          j
        end
      end
      Result.new(job:)
    rescue InvalidPdf
      fail!(password.present? ? "PDFを開けませんでした。パスワードを確認してください。" : "PDFを開けませんでした。パスワード付きの場合は入力してください。")
    end

    private
      def max_mb = [ @limits[:max_file_mb].to_i, @retention[:max_original_mb].to_i ].min
      def fail!(message) = Result.new(error: message)
  end
end
