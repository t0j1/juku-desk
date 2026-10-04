# PDF 本体。PDF_STORAGE=db なら data（bytea）、r2 なら Cloudflare R2（r2_key）に置く。
# （Render Free はファイルが消えるので、ローカルディスクには置かない）
#
# 読むときの優先順: PDF_STORAGE=r2 なら R2 を優先、db なら DB のコピーを優先。
# どちらでも、置き場所が片方にしか無ければそちらから読む（切り替えても既存データは読める）。
class PdfBlob < ApplicationRecord
  KINDS = %w[original output].freeze
  CHUNK_BYTES = 8.megabytes

  belongs_to :pdf_split_job
  belongs_to :pdf_split_output, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :byte_size, :expires_at, presence: true
  validate :stored_somewhere

  scope :expired, -> { where(expires_at: ...Time.current) }
  # data（数十MB）を読み込まない
  scope :without_data, -> { select(column_names - [ "data" ]) }
  scope :in_r2, -> { where.not(r2_key: nil) }
  scope :with_db_copy, -> { where.not(data: nil) }

  def self.retention_days
    Rails.application.config.pdf_splitter.dig(:retention, :days).to_i
  end

  # 保存する。data（String）か path（ファイル）のどちらかを渡す。
  # r2 モードでは R2 に置いて照合し、DB には data を入れない。db モードでは従来どおり data に入れる。
  def self.store!(kind:, pdf_split_job:, expires_at:, pdf_split_output: nil, data: nil, path: nil)
    raise ArgumentError, "data か path のどちらかを渡してください" if data.nil? == path.nil?
    attrs = { kind:, pdf_split_job:, pdf_split_output:, expires_at: }

    if PdfStorage.r2?
      key = "pdf/job-#{pdf_split_job.id}/#{kind}-#{SecureRandom.hex(12)}.pdf"
      result = path ? PdfStorage.r2.put_file(key, path) : PdfStorage.r2.put_string(key, data)
      begin
        PdfStorage.r2.verify!(key, size: result.size, checksum: result.checksum)
        create!(**attrs, r2_key: key, checksum: result.checksum, byte_size: result.size, r2_migrated_at: Time.current)
      rescue Exception # rubocop:disable Lint/RescueException -- 孤児オブジェクトを残さないため、何が起きても消してから投げ直す
        PdfStorage.r2.delete(key) rescue nil
        raise
      end
    else
      data ||= File.binread(path)
      create!(**attrs, data:, byte_size: data.bytesize)
    end
  end

  # 行と、R2 上のオブジェクトをまとめて消す。R2 を先に消す（失敗したら行を残して次回やり直せる）。
  def self.purge(relation)
    keys = relation.in_r2.pluck(:r2_key)
    PdfStorage.r2.delete(keys) if keys.any?
    where(id: relation.select(:id)).delete_all
  end

  # 全体を String で返す。出力 PDF（小さい）用。原本は download_to で読むこと。
  def read
    if read_from_r2?
      PdfStorage.r2.read(r2_key)
    else
      self.class.where(id:).pick(:data)
    end
  end

  # 本体を path にストリーミングで書き出す。全体を String にしない
  def download_to(path)
    if read_from_r2?
      PdfStorage.r2.download_to(r2_key, path)
    else
      File.open(path, "wb") do |f|
        offset = 0
        loop do
          chunk = self.class.where(id:).pick(Arel.sql("substring(data from #{offset + 1} for #{CHUNK_BYTES})"))
          break if chunk.blank?
          f.write(chunk)
          offset += chunk.bytesize
          break if offset >= byte_size
        end
      end
    end
    path
  end

  def in_r2? = r2_key.present?

  def db_copy? = self.class.where(id:).with_db_copy.exists?

  private
    def read_from_r2?
      return false unless in_r2?
      PdfStorage.r2? || !db_copy?
    end

    def stored_somewhere
      return if r2_key.present? || !has_attribute?(:data) || !data.nil?
      errors.add(:base, "データの置き場所（data か r2_key）がありません")
    end
end
