# Render Free はファイルが消えるため、PDF 本体は DB（bytea）に置く
class PdfBlob < ApplicationRecord
  KINDS = %w[original output spread_source].freeze # spread_source = 見開きを分ける前の元PDF（B4 組み直し用）

  belongs_to :pdf_split_job
  belongs_to :pdf_split_output, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :data, :byte_size, :expires_at, presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  WRITE_CHUNK = 4.megabytes

  # ファイルを Ruby の大きな文字列にせず、WRITE_CHUNK ずつ bytea に追記して保存する（512MB 環境向け）
  def self.create_from_file!(job:, kind:, path:, expires_at:)
    blob = create!(pdf_split_job: job, kind:, data: "%PDF".b, byte_size: File.size(path), expires_at:)
    conn = connection.raw_connection
    conn.exec_params("UPDATE pdf_blobs SET data = ''::bytea WHERE id = $1", [ blob.id ])
    File.open(path, "rb") do |f|
      while (chunk = f.read(WRITE_CHUNK))
        conn.exec_params("UPDATE pdf_blobs SET data = data || $1 WHERE id = $2", [ { value: chunk, format: 1 }, blob.id ])
      end
    end
    blob
  end

  def self.retention_days
    Rails.application.config.pdf_splitter.dig(:retention, :days).to_i
  end
end
