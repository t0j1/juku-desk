module PdfSplitter
  # 出力PDFを返す。保存済みが無ければ元PDFから再生成して保存する。
  # PDF 全体を String にしない：with_file は一時ファイルのパスを渡す（ブロックを抜けると消える）。
  class Builder
    # 出力PDFを一時ファイルとして渡す。R2 / DB の本体はファイルへストリーミングで書き出す。
    # source_path を渡すと原本を読み直さない
    def self.with_file(output, source_path: nil, &block)
      if (blob = stored_blob(output))
        return Dir.mktmpdir { |dir| yield blob.download_to(File.join(dir, "out.pdf")) }
      end
      return output.pdf_split_job.with_original_file { |path| with_file(output, source_path: path, &block) } unless source_path

      Dir.mktmpdir do |dir|
        yield generate(output, source_path, File.join(dir, "out.pdf"))
      end
    end

    # 出力PDFを作って保存だけする（SplitJob 用。読み出さない）
    def self.ensure_stored(output, source_path:)
      return if stored_blob(output)

      Dir.mktmpdir { |dir| generate(output, source_path, File.join(dir, "out.pdf")) }
      nil
    end

    # 全体を String で返す。テストや小さい用途向け。配信には with_file を使うこと
    def self.build(output, source_path: nil)
      with_file(output, source_path:) { |path| File.binread(path) }
    end

    def self.within_job_quota?(job, bytes)
      limit = PdfSplitter.config.dig(:retention, :max_outputs_mb_per_job).to_i.megabytes
      job.pdf_blobs.where(kind: "output").sum(:byte_size) + bytes <= limit
    end

    def self.stored_blob(output)
      output.pdf_blobs.without_data.where("expires_at > ?", Time.current).first
    end
    private_class_method :stored_blob

    # out にPDFを作り、保存して（枠に収まれば）、out のパスを返す
    def self.generate(output, source_path, out)
      job = output.pdf_split_job
      Splitter.extract(source_path, out, output.page_from, output.page_to)
      size = File.size(out)
      # 保存はファイルのまま渡す（R2 ならストリーミングでアップロード）
      if within_job_quota?(job, size)
        PdfBlob.store!(kind: "output", pdf_split_job: job, pdf_split_output: output, path: out,
                       expires_at: job.expires_at || PdfBlob.retention_days.days.from_now)
      end
      output.update_column(:byte_size, size)
      out
    end
    private_class_method :generate
  end
end
