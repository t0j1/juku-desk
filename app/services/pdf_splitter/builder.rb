module PdfSplitter
  # 出力PDFを返す。保存済みが無ければ元PDFから再生成して保存する
  class Builder
    # source_path を渡すと原本を読み直さない（SplitJob で16件まとめて作るとき用）
    def self.build(output, source_path: nil)
      if (blob = output.pdf_blobs.without_data.where("expires_at > ?", Time.current).first)
        return blob.read
      end

      job = output.pdf_split_job
      return output.pdf_split_job.with_original_file { |path| build(output, source_path: path) } unless source_path

      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.pdf")
        Splitter.extract(source_path, out, output.page_from, output.page_to)
        size = File.size(out)
        # 保存はファイルのまま渡す（R2 ならストリーミングでアップロード）
        if within_job_quota?(job, size)
          PdfBlob.store!(kind: "output", pdf_split_job: job, pdf_split_output: output, path: out,
                         expires_at: job.expires_at || PdfBlob.retention_days.days.from_now)
        end
        output.update_column(:byte_size, size)
        File.binread(out)
      end
    end

    def self.within_job_quota?(job, bytes)
      limit = PdfSplitter.config.dig(:retention, :max_outputs_mb_per_job).to_i.megabytes
      job.pdf_blobs.where(kind: "output").sum(:byte_size) + bytes <= limit
    end
  end
end
