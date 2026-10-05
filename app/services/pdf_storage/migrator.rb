module PdfStorage
  # 既存の PDF（DB の bytea）を R2 へ移す。1 件ずつ処理し、途中で止まっても再実行できる。
  #   - 移行済み（r2_key あり）はスキップ。キーは blob ごとに固定なので、アップロード後・記録前に落ちても上書きで済む
  #   - DB から一時ファイルへストリーミングで書き出し、そのファイルを R2 へ送る（全体を String にしない）
  #   - アップロード後に R2 のサイズとチェックサムを照合し、一致しなければオブジェクトを消して中断する
  # DB のコピーは消さない（消すのは purge_db_copies! だけ）。
  class Migrator
    Report = Struct.new(:migrated, :skipped, keyword_init: true)

    def initialize(r2: PdfStorage.r2, log: ->(msg) { puts msg }, limit: nil)
      @r2 = r2
      @log = log
      @limit = limit
    end

    def migrate!
      report = Report.new(migrated: 0, skipped: 0)
      scope = PdfBlob.without_data.with_db_copy.where(r2_key: nil).where("expires_at > ?", Time.current).order(:id)
      scope = scope.limit(@limit) if @limit
      scope.find_each do |blob|
        migrate_one(blob)
        report.migrated += 1
        @log.call("移行しました: blob #{blob.id}（#{blob.byte_size} バイト）")
      end
      report.skipped = PdfBlob.in_r2.count
      @log.call("完了: 今回 #{report.migrated} 件を移行（すでに R2 にある件数: #{report.skipped}）")
      report
    end

    # R2 に照合済みのコピーがある行だけ、DB の data を空にする。照合し直して 1 件でも違えば中断する。
    def purge_db_copies!
      purged = 0
      PdfBlob.without_data.with_db_copy.in_r2.order(:id).find_each do |blob|
        @r2.verify!(blob.r2_key, size: blob.byte_size, checksum: blob.checksum)
        PdfBlob.where(id: blob.id).update_all(data: nil)
        purged += 1
      end
      @log.call("DB のコピーを #{purged} 件削除しました")
      purged
    end

    private
      def migrate_one(blob)
        key = "pdf/job-#{blob.pdf_split_job_id}/#{blob.kind}-#{blob.id}.pdf"
        Dir.mktmpdir("pdf_migrate") do |dir|
          path = File.join(dir, "blob.pdf")
          blob.download_to(path)
          raise ChecksumMismatch, "DB から読んだサイズが一致しません（blob #{blob.id}: #{File.size(path)} / #{blob.byte_size}）" unless File.size(path) == blob.byte_size

          result = @r2.put_file(key, path)
          begin
            @r2.verify!(key, size: blob.byte_size, checksum: result.checksum)
          rescue ChecksumMismatch
            @r2.delete(key)
            raise
          end
          blob.update_columns(r2_key: key, checksum: result.checksum, r2_migrated_at: Time.current)
        end
      end
  end
end
