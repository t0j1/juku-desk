require "test_helper"
require "open3"

# パスワード付きPDFの処理。パスワードはコマンド引数に載せず、0600 の一時ファイル（--password-file）で渡し、必ず消す
class PdfSplitter::SplitterPasswordTest < ActiveSupport::TestCase
  PASSWORD = "s3cret-pass-#{SecureRandom.hex(4)}".freeze

  setup do
    skip "qpdf が必要です" unless system("which qpdf", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir
    @plain = File.join(@dir, "plain.pdf")
    @encrypted = File.join(@dir, "encrypted.pdf")
    FileUtils.cp(file_fixture("workbook_p1.pdf"), @plain)
    _o, err, st = Open3.capture3("qpdf", "--encrypt", PASSWORD, PASSWORD, "256", "--", @plain, @encrypted)
    flunk "暗号化PDFを作れませんでした: #{err}" unless st.success?
  end

  teardown { FileUtils.rm_rf(@dir) }

  # Open3.capture3 に渡された引数を記録しつつ、本物を呼ぶ。実行中の --password-file の中身と権限も控える
  def spying_on_qpdf
    calls = []
    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) do |*args, **opts, &blk|
      pw_arg = args.find { |a| a.to_s.start_with?("--password-file=") }
      info = { args: args.map(&:to_s) }
      if pw_arg
        path = pw_arg.to_s.delete_prefix("--password-file=")
        info.merge!(path:, content: File.read(path), mode: File.stat(path).mode & 0o777, dir_mode: File.stat(File.dirname(path)).mode & 0o777)
      end
      calls << info
      original.call(*args, **opts, &blk)
    end
    yield calls
  ensure
    Open3.define_singleton_method(:capture3, original)
  end

  test "decrypt works with the right password and fails with a wrong one" do
    out = File.join(@dir, "out.pdf")
    PdfSplitter::Splitter.decrypt(@encrypted, out, password: PASSWORD)
    assert_equal 20, PdfSplitter::Splitter.page_count(out)
    assert_raises(PdfSplitter::InvalidPdf) { PdfSplitter::Splitter.decrypt(@encrypted, File.join(@dir, "bad.pdf"), password: "wrong") }
  end

  test "page count and page extraction accept the password" do
    assert_equal 20, PdfSplitter::Splitter.page_count(@encrypted, password: PASSWORD)
    out = File.join(@dir, "part.pdf")
    PdfSplitter::Splitter.extract(@encrypted, out, 2, 4, password: PASSWORD)
    assert_equal 3, PdfSplitter::Splitter.page_count(out)
    assert_raises(PdfSplitter::InvalidPdf) { PdfSplitter::Splitter.page_count(@encrypted) }
  end

  test "decrypt_to_string decrypts to a plain PDF" do
    plain = PdfSplitter::Splitter.decrypt_to_string(File.binread(@encrypted), password: PASSWORD)
    assert_equal 20, PdfSplitter::Splitter.page_count_of(plain)
  end

  test "the password never appears in the command line; it is passed through a 0600 file" do
    spying_on_qpdf do |calls|
      out = File.join(@dir, "out.pdf")
      PdfSplitter::Splitter.decrypt(@encrypted, out, password: PASSWORD)
      PdfSplitter::Splitter.page_count(@encrypted, password: PASSWORD)
      PdfSplitter::Splitter.extract(@encrypted, File.join(@dir, "p.pdf"), 1, 2, password: PASSWORD)
      PdfSplitter::Splitter.decrypt_to_string(File.binread(@encrypted), password: PASSWORD)

      assert_equal 4, calls.size
      calls.each do |call|
        assert call[:args].none? { |a| a.include?(PASSWORD) }, "コマンド引数にパスワードが含まれている: #{call[:args]}"
        assert call[:args].none? { |a| a.start_with?("--password=") }
        assert_equal PASSWORD, call[:content]
        assert_equal 0o600, call[:mode]
        assert_equal 0o700, call[:dir_mode]
      end
    end
  end

  test "the password file is removed after success" do
    spying_on_qpdf do |calls|
      PdfSplitter::Splitter.page_count(@encrypted, password: PASSWORD)
      assert_not File.exist?(calls.first[:path])
      assert_not Dir.exist?(File.dirname(calls.first[:path]))
    end
  end

  test "the password file is removed even when qpdf fails or raises" do
    spying_on_qpdf do |calls|
      assert_raises(PdfSplitter::InvalidPdf) { PdfSplitter::Splitter.page_count(@encrypted, password: "wrong-#{PASSWORD}") }
      assert_not File.exist?(calls.first[:path])

      seen = nil
      Open3.define_singleton_method(:capture3) do |*args, **|
        seen = args.find { |a| a.to_s.start_with?("--password-file=") }.to_s.delete_prefix("--password-file=")
        raise Errno::ENOENT, "qpdf"
      end
      assert_raises(Errno::ENOENT) { PdfSplitter::Splitter.decrypt(@encrypted, File.join(@dir, "x.pdf"), password: PASSWORD) }
      assert seen.present?
      assert_not File.exist?(seen), "例外のときも一時ファイルが消える"
    end
  end

  test "without a password no password option is passed and no file is made" do
    spying_on_qpdf do |calls|
      PdfSplitter::Splitter.page_count(@plain)
      assert calls.first[:args].none? { |a| a.include?("password") }
    end
  end
end
