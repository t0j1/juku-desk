require "test_helper"
require "aws-sdk-s3"

class PdfStorage::R2Test < ActiveSupport::TestCase
  def r2(client) = PdfStorage::R2.new(client:, bucket: "test-bucket")

  test "put_file sends the file with its SHA-256 and reports size and checksum" do
    client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    Tempfile.create([ "x", ".pdf" ]) do |f|
      f.binmode.write(PDF_BYTES)
      f.flush
      result = r2(client).put_file("pdf/a.pdf", f.path)
      assert_equal [ PDF_BYTES.bytesize, Digest::SHA256.hexdigest(PDF_BYTES) ], [ result.size, result.checksum ]
    end
    req = client.api_requests.find { |r| r[:operation_name] == :put_object }
    assert_equal "test-bucket", req[:params][:bucket]
    assert_equal "pdf/a.pdf", req[:params][:key]
    assert_equal "SHA256", req[:params][:checksum_algorithm]
    assert_equal [ Digest::SHA256.digest(PDF_BYTES) ].pack("m0"), req[:params][:checksum_sha256]
  end

  test "each_object lists keys under a prefix across pages" do
    client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    t = Time.utc(2026, 10, 1)
    client.stub_responses(:list_objects_v2, [
      { contents: [ { key: "pdf/a.pdf", last_modified: t } ], is_truncated: true, next_continuation_token: "t" },
      { contents: [ { key: "pdf/b.pdf", last_modified: t + 1 } ], is_truncated: false }
    ])
    entries = r2(client).each_object(prefix: "pdf/").to_a
    assert_equal %w[pdf/a.pdf pdf/b.pdf], entries.map(&:key)
    assert_equal t, entries.first.last_modified
    assert_equal "pdf/", client.api_requests.first[:params][:prefix]
  end

  test "verify! passes when size and checksum match and fails otherwise" do
    sha = Digest::SHA256.hexdigest(PDF_BYTES)
    client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    client.stub_responses(:head_object, content_length: PDF_BYTES.bytesize, checksum_sha256: [ Digest::SHA256.digest(PDF_BYTES) ].pack("m0"))
    assert r2(client).verify!("k", size: PDF_BYTES.bytesize, checksum: sha)
    assert_raises(PdfStorage::ChecksumMismatch) { r2(client).verify!("k", size: PDF_BYTES.bytesize + 1, checksum: sha) }
    assert_raises(PdfStorage::ChecksumMismatch) { r2(client).verify!("k", size: PDF_BYTES.bytesize, checksum: "0" * 64) }
  end

  test "verify! re-reads the object when R2 returns no checksum" do
    client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    client.stub_responses(:head_object, content_length: PDF_BYTES.bytesize)
    client.stub_responses(:get_object, body: PDF_BYTES)
    assert r2(client).verify!("k", size: PDF_BYTES.bytesize, checksum: Digest::SHA256.hexdigest(PDF_BYTES))
    client.stub_responses(:get_object, body: PDF_BYTES.reverse)
    assert_raises(PdfStorage::ChecksumMismatch) { r2(client).verify!("k", size: PDF_BYTES.bytesize, checksum: Digest::SHA256.hexdigest(PDF_BYTES)) }
  end

  test "a missing object fails verification" do
    client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    client.stub_responses(:head_object, "NotFound")
    assert_raises(PdfStorage::ChecksumMismatch) { r2(client).verify!("k", size: 1, checksum: "x") }
  end

  test "credentials come from the environment and a missing one is reported by name" do
    keys = %w[R2_ACCOUNT_ID R2_ENDPOINT R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET]
    saved = keys.index_with { |k| ENV.delete(k) }
    error = assert_raises(PdfStorage::NotConfigured) { PdfStorage::R2.new.bucket }
    assert_match(/R2_BUCKET/, error.message)
    ENV.update("R2_ACCOUNT_ID" => "acct", "R2_ACCESS_KEY_ID" => "id", "R2_SECRET_ACCESS_KEY" => "secret", "R2_BUCKET" => "b")
    client = PdfStorage::R2.new.client
    assert_equal "https://acct.r2.cloudflarestorage.com", client.config.endpoint.to_s
  ensure
    keys.each { |k| saved[k].nil? ? ENV.delete(k) : ENV[k] = saved[k] }
  end
end
