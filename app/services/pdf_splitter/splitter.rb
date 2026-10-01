require "open3"

module PdfSplitter
  # qpdf は必ず配列引数で呼ぶ（シェルを通さない＝コマンドインジェクション防止）
  class Splitter
    def self.extract(input_path, output_path, from, to, password: nil)
      cmd = [ "qpdf", "--empty" ]
      cmd << "--password=#{password}" if password.present?
      cmd += [ "--pages", input_path.to_s, "#{Integer(from)}-#{Integer(to)}", "--", output_path.to_s ]
      _out, err, st = Open3.capture3(*cmd)
      # 終了コード 3 は「警告あり・出力成功」
      raise SplitError, err.presence || "qpdf failed" unless st.success? || st.exitstatus == 3
      output_path
    end

    def self.page_count(path, password: nil)
      cmd = [ "qpdf" ]
      cmd << "--password=#{password}" if password.present?
      cmd += [ "--show-npages", path.to_s ]
      out, err, st = Open3.capture3(*cmd)
      raise InvalidPdf, err.presence || "page count failed" unless st.success? || st.exitstatus == 3
      out.to_i
    end

    # パスワード付きPDFを復号した平文PDFに変換する（パスワードは保存しない）
    def self.decrypt_to_string(data, password:)
      with_tempfile(data) do |input|
        Dir.mktmpdir do |dir|
          out = File.join(dir, "out.pdf")
          _o, err, st = Open3.capture3("qpdf", "--password=#{password}", "--decrypt", input, out)
          raise InvalidPdf, err.presence || "decrypt failed" unless st.success? || st.exitstatus == 3
          File.binread(out)
        end
      end
    end

    def self.extract_to_string(data, from, to)
      with_tempfile(data) do |input|
        Dir.mktmpdir do |dir|
          out = File.join(dir, "out.pdf")
          extract(input, out, from, to)
          File.binread(out)
        end
      end
    end

    def self.page_count_of(data)
      with_tempfile(data) { |path| page_count(path) }
    end

    def self.with_tempfile(data)
      Tempfile.create([ "pdf_splitter", ".pdf" ], binmode: true) do |f|
        f.write(data)
        f.flush
        yield f.path
      end
    end
  end
end
