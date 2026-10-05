namespace :pdf_blobs do
  desc "DB（bytea）の PDF を R2 へ移す。1 件ずつ・再実行可。LIMIT=件数 で上限。DB のコピーは消さない"
  task migrate_to_r2: :environment do
    PdfStorage::Migrator.new(limit: ENV["LIMIT"].presence&.to_i).migrate!
  end

  desc "R2 に照合済みのコピーがある PDF の DB 側 data を消す（元に戻せない）。CONFIRM=yes を付けたときだけ動く"
  task purge_db_copies: :environment do
    abort "DB のコピーを消すと PDF_STORAGE=db に戻せなくなります。実行するなら CONFIRM=yes を付けてください。" unless ENV["CONFIRM"] == "yes"
    PdfStorage::Migrator.new.purge_db_copies!
  end
end
