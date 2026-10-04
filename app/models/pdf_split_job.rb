class PdfSplitJob < ApplicationRecord
  PATTERNS = { 0 => "P1 前後分離型", 1 => "P2 交互型", 2 => "P3 見開き型", 3 => "P4 手動範囲指定", 4 => "P5 N等分" }.freeze
  MIN_CONFIDENCE = 0.6

  belongs_to :user
  has_many :outputs, -> { order(:position, :page_from) }, class_name: "PdfSplitOutput", dependent: :delete_all
  has_many :page_analyses, -> { order(:page) }, class_name: "PdfSplitPageAnalysis", dependent: :delete_all
  # R2 のオブジェクトも消すため、行を消す前（outputs より先）に PdfBlob.purge を通す
  has_many :pdf_blobs, dependent: :delete_all
  before_destroy(prepend: true) { PdfBlob.purge(pdf_blobs) }

  enum :status, { uploaded: 0, analyzing: 1, analyzed: 2, splitting: 3, done: 4, failed: 5 }

  validates :original_filename, presence: true

  scope :created_today, -> { where(created_at: Time.current.all_day) }

  STALE_AFTER = 10.minutes

  # プロセスごと落ちると AnalyzeJob/SplitJob の rescue が走らず analyzing/splitting のまま残るので、
  # 一定時間進まないものは failed に倒して「再試行」を出す（解析は25ページごとに updated_at を進める）
  # 印刷ページの一覧用：分割済みのみ・新しい順・ファイル名で絞り込み
  def self.printable(query = nil)
    scope = done.order(created_at: :desc)
    scope = scope.where("original_filename ILIKE ?", "%#{sanitize_sql_like(query.to_s.strip)}%") if query.present?
    scope
  end

  def fail_if_stale!
    return unless (analyzing? || splitting?) && updated_at < STALE_AFTER.ago
    update!(status: :failed, error_message: STALE_MESSAGE)
  end

  STALE_MESSAGE = "処理中にサーバーが停止しました（メモリ不足の可能性）。「再試行」でやり直せます。".freeze

  # 一覧を開いたときにも、止まったままのものを failed に倒す
  def self.fail_stale!
    where(status: %i[analyzing splitting]).where(updated_at: ...STALE_AFTER.ago).find_each(&:fail_if_stale!)
  end

  def original_blob
    pdf_blobs.without_data.where(kind: "original").where("expires_at > ?", Time.current).first
  end

  # 原本を Ruby の大きな文字列にせず、DB / R2 からディスクへストリーミングで書き出してパスを渡す
  # （512MB 環境で 27MB の原本を何度も読み込むとメモリ不足で落ちるため）。
  # 書き出したファイルは tmp/pdf_cache に残して、サムネイルや分割で使い回す（毎回読むと1件10秒以上かかる）
  CACHE_DIR = Rails.root.join("tmp", "pdf_cache")
  CACHE_LOCK = Mutex.new

  def with_original_file
    yield original_cache_path
  end

  def original_cache_path
    blob = original_blob
    raise PdfSplitter::Error, "元PDFの保存期限が切れています。もう一度アップロードしてください。" unless blob

    path = CACHE_DIR.join("#{id}-#{blob.id}-#{blob.created_at.to_f.to_s.delete('.')}.pdf")
    CACHE_LOCK.synchronize do
      return path.to_s if path.exist? && path.size == blob.byte_size
      FileUtils.mkdir_p(CACHE_DIR)
      tmp = "#{path}.#{Process.pid}.part"
      blob.download_to(tmp)
      File.rename(tmp, path)
    end
    path.to_s
  end

  def self.prune_original_cache(older_than: 1.day.ago)
    Dir.glob(CACHE_DIR.join("*")).each { |p| File.delete(p) if File.mtime(p) < older_than rescue nil }
  end

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
