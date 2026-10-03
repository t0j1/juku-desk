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

  STALE_AFTER = 10.minutes

  # プロセスごと落ちると AnalyzeJob/SplitJob の rescue が走らず analyzing/splitting のまま残るので、
  # 一定時間進まないものは failed に倒して再アップロードを促す
  def fail_if_stale!
    return unless (analyzing? || splitting?) && updated_at < STALE_AFTER.ago
    update!(status: :failed, error_message: "処理中にサーバーが停止しました。ページ数の少ないPDFで再度お試しください。")
  end

  def original_blob
    pdf_blobs.where(kind: "original").where("expires_at > ?", Time.current).first
  end

  CHUNK_BYTES = 1.megabyte

  # 原本を Ruby の大きな文字列にせず、DB から 1MB ずつ tempfile に書き出してパスを渡す
  # （512MB 環境で 27MB の原本を何度も読み込むとメモリ不足で落ちるため）
  def with_original_file
    blob_id, size = pdf_blobs.where(kind: "original").where("expires_at > ?", Time.current).pick(:id, :byte_size)
    raise PdfSplitter::Error, "元PDFの保存期限が切れています。もう一度アップロードしてください。" unless blob_id

    Tempfile.create([ "pdf_original", ".pdf" ], binmode: true) do |f|
      offset = 0
      loop do
        chunk = PdfBlob.where(id: blob_id).pick(Arel.sql("substring(data from #{offset + 1} for #{CHUNK_BYTES})"))
        break if chunk.blank?
        f.write(chunk)
        offset += chunk.bytesize
        break if size && offset >= size
      end
      f.flush
      yield f.path
    end
  end

  def original_blob_data
    original_blob&.data or raise PdfSplitter::Error, "元PDFの保存期限が切れています。もう一度アップロードしてください。"
  end

  # data 列（数十MB）を読み込まないように期限だけ取る
  def expires_at
    pdf_blobs.where(kind: "original").where("expires_at > ?", Time.current).pick(:expires_at)
  end

  def pattern_label
    PATTERNS[pattern]
  end

  def auto_detected?
    pattern.present? && confidence.to_f >= MIN_CONFIDENCE
  end
end
