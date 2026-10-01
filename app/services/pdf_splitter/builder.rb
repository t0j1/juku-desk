module PdfSplitter
  # 出力PDFを返す。保存済みが無ければ元PDFから再生成して保存する
  class Builder
    def self.build(output)
      if (blob = output.pdf_blobs.where("expires_at > ?", Time.current).first)
        return blob.data
      end

      job = output.pdf_split_job
      pdf = Splitter.extract_to_string(job.original_blob_data, output.page_from, output.page_to)
      if within_job_quota?(job, pdf.bytesize)
        output.pdf_blobs.create!(pdf_split_job: job, kind: "output", data: pdf, byte_size: pdf.bytesize,
                                 expires_at: job.expires_at || PdfBlob.retention_days.days.from_now)
      end
      output.update_column(:byte_size, pdf.bytesize)
      pdf
    end

    def self.within_job_quota?(job, bytes)
      limit = PdfSplitter.config.dig(:retention, :max_outputs_mb_per_job).to_i.megabytes
      job.pdf_blobs.where(kind: "output").sum(:byte_size) + bytes <= limit
    end
  end
end
