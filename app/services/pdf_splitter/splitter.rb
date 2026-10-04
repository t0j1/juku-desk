require "open3"

module PdfSplitter
  # qpdf は必ず配列引数で呼ぶ（シェルを通さない＝コマンドインジェクション防止）
  class Splitter
    def self.extract(input_path, output_path, from, to, password: nil)
      with_password_args(password) do |pw|
        range = "#{Integer(from)}-#{Integer(to)}"
        # --pages の中で渡せるのは --password= だけ（--password-file は不可）。パスワードを引数に載せないよう、
        # パスワード付きのときは暗号化PDFを入力に指定し、そのページを取り出す（--pages .）
        cmd = if pw.empty?
          [ "qpdf", "--empty", "--pages", input_path.to_s, range, "--", output_path.to_s ]
        else
          [ "qpdf", *pw, "--decrypt", input_path.to_s, "--pages", ".", range, "--", output_path.to_s ]
        end
        _out, err, st = Open3.capture3(*cmd)
        # 終了コード 3 は「警告あり・出力成功」
        raise SplitError, err.presence || "qpdf failed" unless st.success? || st.exitstatus == 3
      end
      output_path
    end

    def self.page_count(path, password: nil)
      with_password_args(password) do |pw|
        out, err, st = Open3.capture3("qpdf", *pw, "--show-npages", path.to_s)
        raise InvalidPdf, err.presence || "page count failed" unless st.success? || st.exitstatus == 3
        out.to_i
      end
    end

    # パスワード付きPDFを復号した平文PDFをファイルに書き出す（パスワードは保存しない）
    def self.decrypt(input, output, password:)
      with_password_args(password) do |pw|
        _o, err, st = Open3.capture3("qpdf", *pw, "--decrypt", input.to_s, output.to_s)
        raise InvalidPdf, err.presence || "decrypt failed" unless st.success? || st.exitstatus == 3
      end
      output
    end

    # パスワード付きPDFを復号した平文PDFに変換する（パスワードは保存しない）
    def self.decrypt_to_string(data, password:)
      with_tempfile(data) do |input|
        Dir.mktmpdir do |dir|
          out = File.join(dir, "out.pdf")
          decrypt(input, out, password:)
          File.binread(out)
        end
      end
    end

    def self.extract_to_string(data, from, to)
      with_tempfile(data) { |input| extract_path_to_string(input, from, to) }
    end

    def self.extract_path_to_string(input, from, to)
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.pdf")
        extract(input, out, from, to)
        File.binread(out)
      end
    end

    def self.page_count_of(data)
      with_tempfile(data) { |path| page_count(path) }
    end

    # パスワードをコマンド引数に載せない（プロセス一覧の ps で見えてしまうため）。
    # 権限 0600 の一時ファイルに書き、qpdf には --password-file で渡す。ブロックを抜けたら（例外でも）必ず消す。
    # パスワードが空なら引数は付けない
    def self.with_password_args(password)
      return yield([]) if password.blank?

      Dir.mktmpdir("qpdf_pw") do |dir| # mktmpdir は 0700
        path = File.join(dir, "password")
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(password) }
        yield([ "--password-file=#{path}" ])
      end
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
