# Render Free はファイルが消えるため、PDF 本体は DB（bytea）に置く
class PdfBlob < ApplicationRecord
  KINDS = %w[original output spread_source].freeze # spread_source = 見開きを分ける前の元PDF（B4 組み直し用）

  belongs_to :pdf_split_job
  belongs_to :pdf_split_output, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :data, :byte_size, :expires_at, presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  def self.retention_days
    Rails.application.config.pdf_splitter.dig(:retention, :days).to_i
  end
end
