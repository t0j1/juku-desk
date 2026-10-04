require "digest"

# R2 のスタブ。メモリ上に置くだけで、PdfStorage::R2 と同じメソッドを持つ。
class FakeR2
  attr_reader :objects, :puts, :deletes
  attr_accessor :corrupt_puts

  def initialize
    @objects = {}
    @puts = []
    @deletes = []
    @corrupt_puts = false
  end

  def put_file(key, path) = put_string(key, File.binread(path))

  def put_string(key, data)
    checksum = Digest::SHA256.hexdigest(data)
    stored = data.b
    stored.setbyte(0, stored.getbyte(0) ^ 0xFF) if corrupt_puts && stored.bytesize.positive? # 転送中に壊れた想定（サイズは同じ）
    @objects[key] = stored
    @puts << key
    PdfStorage::R2::Result.new(size: data.bytesize, checksum:)
  end

  def head(key)
    data = @objects[key] or return nil
    PdfStorage::R2::Result.new(size: data.bytesize, checksum: Digest::SHA256.hexdigest(data))
  end

  def verify!(key, size:, checksum:)
    remote = head(key) or raise PdfStorage::ChecksumMismatch, "R2 にオブジェクトがありません（#{key}）"
    raise PdfStorage::ChecksumMismatch, "サイズが一致しません" unless remote.size == size
    raise PdfStorage::ChecksumMismatch, "チェックサムが一致しません" unless remote.checksum == checksum
    true
  end

  def download_to(key, path)
    File.binwrite(path, @objects.fetch(key))
    path
  end

  def read(key) = @objects.fetch(key)

  def delete(keys)
    Array(keys).each { |k| @objects.delete(k); @deletes << k }
  end
end

module PdfStorageTestHelper
  PDF_BYTES = ("%PDF-1.4\n" + "x" * 1000 + "\n%%EOF\n").b.freeze

  # PDF_STORAGE と R2 の差し替えをブロックの間だけ有効にする
  def with_pdf_storage(mode, r2: FakeR2.new)
    old_env = ENV["PDF_STORAGE"]
    ENV["PDF_STORAGE"] = mode
    PdfStorage.r2 = r2
    yield r2
  ensure
    old_env.nil? ? ENV.delete("PDF_STORAGE") : ENV["PDF_STORAGE"] = old_env
    PdfStorage.r2 = nil
  end

  def new_job(user: users(:staff))
    user.pdf_split_jobs.create!(original_filename: "sample.pdf", page_count: 1)
  end

  def store_blob(job, data: PDF_BYTES, kind: "original", expires_at: 7.days.from_now)
    PdfBlob.store!(kind:, pdf_split_job: job, data:, expires_at:)
  end
end

ActiveSupport.on_load(:active_support_test_case) { include PdfStorageTestHelper }
