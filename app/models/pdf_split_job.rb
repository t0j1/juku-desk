class PdfSplitJob < ApplicationRecord
  PATTERNS = { 0 => "P1 前後分離型", 1 => "P2 交互型", 2 => "P3 見開き型", 3 => "P4 手動範囲指定", 4 => "P5 N等分" }.freeze
  MIN_CONFIDENCE = 0.6

  belongs_to :user
  has_many :outputs, -> { order(:position, :page_from) }, class_name: "PdfSplitOutput", dependent: :delete_all
  has_many :page_analyses, -> { order(:page) }, class_name: "PdfSplitPageAnalysis", dependent: :delete_all
  has_many :pdf_blobs, dependent: :delete_all

  enum :status, { uploaded: 0, analyzing: 1, analyzed: 2, splitting: 3, done: 4, failed: 5 }

  validates :original_filename, presence: true

  scope :created_today, -> { where(created_at: Time.current.all_day) }

  def original_blob
    pdf_blobs.where(kind: "original").where("expires_at > ?", Time.current).first
  end

  def original_blob_data
    original_blob&.data or raise PdfSplitter::Error, "元PDFの保存期限が切れています。もう一度アップロードしてください。"
  end

  def expires_at
    original_blob&.expires_at
  end

  def pattern_label
    PATTERNS[pattern]
  end

  def auto_detected?
    pattern.present? && confidence.to_f >= MIN_CONFIDENCE
  end
end
