require "aws-sdk-s3"
require "digest"

module PdfStorage
  # Cloudflare R2（S3 互換）の薄いアダプタ。認証情報はすべて環境変数から読む:
  #   R2_ACCOUNT_ID（または R2_ENDPOINT）, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
  # アップロードは 1 回の PutObject（ファイルは IO のままストリーミング）なので、ETag は MD5 になる。
  class R2
    CHUNK_BYTES = 8 * 1024 * 1024

    Result = Struct.new(:size, :checksum, keyword_init: true)

    def initialize(client: nil, bucket: nil)
      @client = client
      @bucket = bucket
    end

    def bucket = @bucket ||= env!("R2_BUCKET")

    def client
      @client ||= Aws::S3::Client.new(
        endpoint: endpoint,
        region: "auto",
        access_key_id: env!("R2_ACCESS_KEY_ID"),
        secret_access_key: env!("R2_SECRET_ACCESS_KEY"),
        force_path_style: true,
        # R2 は SDK 既定の追加チェックサム（CRC32 など）を拒否することがあるので、明示したときだけ付ける
        request_checksum_calculation: "when_required",
        response_checksum_validation: "when_required"
      )
    end

    # path のファイルをアップロードする。SHA-256 は先にファイルをなめて求める（メモリには載せない）。
    def put_file(key, path)
      checksum = Digest::SHA256.file(path).hexdigest
      File.open(path, "rb") { |io| put(key, io, checksum) }
      Result.new(size: File.size(path), checksum:)
    end

    def put_string(key, data)
      checksum = Digest::SHA256.hexdigest(data)
      put(key, StringIO.new(data), checksum)
      Result.new(size: data.bytesize, checksum:)
    end

    # R2 上のオブジェクトを取り出す。（サイズ, SHA-256）を返す。無ければ nil
    def head(key)
      res = client.head_object(bucket:, key:, checksum_mode: "ENABLED")
      sha = res.checksum_sha256 && res.checksum_sha256.unpack1("m0").unpack1("H*")
      Result.new(size: res.content_length, checksum: sha)
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end

    # 期待するサイズとチェックサムと一致するか照合する。違えば ChecksumMismatch。
    # head でチェックサムが返らないときは、ストリーミングで読み直して求める（R2 は転送料がかからない）
    def verify!(key, size:, checksum:)
      remote = head(key) or raise ChecksumMismatch, "R2 にオブジェクトがありません（#{key}）"
      raise ChecksumMismatch, "サイズが一致しません（#{key}: DB #{size} / R2 #{remote.size}）" unless remote.size == size
      actual = remote.checksum || stream_sha256(key)
      raise ChecksumMismatch, "チェックサムが一致しません（#{key}）" unless actual == checksum
      true
    end

    # ファイルへストリーミングで書き出す（全体を String にしない）
    def download_to(key, path)
      File.open(path, "wb") { |f| client.get_object(bucket:, key:) { |chunk| f.write(chunk) } }
      path
    end

    def read(key)
      client.get_object(bucket:, key:).body.read
    end

    def delete(keys)
      keys = Array(keys).compact
      keys.each_slice(1000) do |slice|
        res = client.delete_objects(bucket:, delete: { objects: slice.map { |k| { key: k } }, quiet: true })
        raise "R2 の削除に失敗しました（#{res.errors.map(&:code).uniq.join(', ')}）" if res.errors.any?
      end
    end

    private
      def stream_sha256(key)
        digest = Digest::SHA256.new
        client.get_object(bucket:, key:) { |chunk| digest << chunk }
        digest.hexdigest
      end

      def put(key, io, checksum)
        client.put_object(bucket:, key:, body: io, content_type: "application/pdf",
                          checksum_algorithm: "SHA256", checksum_sha256: [ [ checksum ].pack("H*") ].pack("m0"))
      end

      def endpoint
        ENV["R2_ENDPOINT"].presence || "https://#{env!('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com"
      end

      def env!(name)
        ENV[name].presence or raise NotConfigured, "環境変数 #{name} が設定されていません"
      end
  end
end
