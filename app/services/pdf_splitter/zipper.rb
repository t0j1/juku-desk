require "zip"

module PdfSplitter
  class Zipper
    # 全体を String で返す（テスト用）。配信には with_zip を使うこと
    def self.zip(outputs) = with_zip(outputs) { |path| File.binread(path) }

    # ZIP を一時ファイルに書く。各出力も一時ファイルからコピーするので、PDF を String にしない
    def self.with_zip(outputs)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "outputs.zip")
        Zip::OutputStream.open(path) do |zos|
          outputs.each do |o|
            Builder.with_file(o) do |pdf|
              zos.put_next_entry(o.filename)
              File.open(pdf, "rb") { |f| IO.copy_stream(f, zos) }
            end
          end
        end
        yield path
      end
    end
  end
end
