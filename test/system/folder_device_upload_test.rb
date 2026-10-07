require "application_system_test_case"
require "prawn"

# 問題フォルダ画面で、端末のファイル（JPEG/PNG/PDF）を直接入れる（ブラウザで縮小・検出・PDF の画像化をして POST /marking へ）
class FolderDeviceUploadTest < ApplicationSystemTestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    @folder = QuestionFolder.create!(name: "10月")
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def pdf_path(name, pages: 2, **opts)
    path = File.join(@dir, name)
    Prawn::Document.generate(path, **opts) do |pdf|
      pages.times do |i|
        pdf.start_new_page if i.positive?
        pdf.text "#{name} page #{i + 1}", size: 40
        pdf.fill_rectangle [ 50, 400 - i * 3 ], 200, 80 # ページごとに違う絵にする
      end
    end
    path
  end

  def pick(*paths)
    visit question_folder_path(@folder)
    attach_file "folder-files", paths, visible: :all
  end

  def folder_upload_count = @folder.folder_uploads.count

  test "several JPEG/PNG pictures are imported into the folder" do
    pick write_marking_png("a.png", frames: [ [ 100, 100, 300, 200 ] ], seed: 1), write_marking_png("b.png", frames: [ [ 50, 60, 200, 150 ] ], seed: 2)
    assert_selector "#device-upload-result", text: "追加 2 枚・重複 0 枚・失敗 0 件"
    assert_equal 2, folder_upload_count
    assert_selector "#folder-uploads li", count: 2
    assert_text "構造化は順次"
    assert Upload.all.all? { |u| u.crop_regions.size == 1 } # 赤枠が検出されて保存されている
  end

  test "a multi-page PDF becomes one image per page" do
    pick pdf_path("two.pdf", pages: 3)
    assert_selector "#device-upload-result", text: "追加 3 枚", wait: 30
    assert_equal 3, folder_upload_count
  end

  test "choosing the same picture again makes no duplicate but still puts it in the folder" do
    path = write_marking_png("same.png", frames: [ [ 100, 100, 300, 200 ] ], seed: 3)
    other = QuestionFolder.create!(name: "別")
    pick path
    assert_selector "#device-upload-result", text: "追加 1 枚"
    assert_difference -> { Upload.count } => 0 do
      visit question_folder_path(other)
      attach_file "folder-files", path, visible: :all
      assert_selector "#device-upload-result", text: "追加 0 枚・重複 1 枚"
    end
    assert_equal 1, other.folder_uploads.count
  end

  test "a PDF over the size limit, one over the page limit and a broken or encrypted PDF are refused with reasons while the others continue" do
    big = File.join(@dir, "big.pdf")
    File.binwrite(big, "%PDF-1.4\n" + "0" * (21 * 1024 * 1024))
    many = pdf_path("many.pdf", pages: 51)
    broken = File.join(@dir, "broken.pdf")
    File.binwrite(broken, "not a pdf at all")
    good = write_marking_png("ok.png", frames: [ [ 100, 100, 300, 200 ] ], seed: 4)
    pick big, many, broken, good
    assert_selector "#device-upload-result", text: "追加 1 枚・重複 0 枚・失敗 3 件", wait: 60
    assert_selector "[data-failures] li", text: /big\.pdf：PDF は 1 ファイル 20MB まで/
    assert_selector "[data-failures] li", text: /many\.pdf：PDF は 50 ページまでです（51 ページ）/
    assert_selector "[data-failures] li", text: /broken\.pdf：PDF を読めませんでした/
    assert_equal 1, folder_upload_count
  end

  test "an encrypted PDF is refused with its own reason" do
    path = File.join(@dir, "locked.pdf")
    Prawn::Document.generate(path) do |pdf|
      pdf.encrypt_document(user_password: "secret", owner_password: "owner")
      pdf.text "secret"
    end
    pick path
    assert_selector "[data-failures] li", text: /locked\.pdf：パスワード付き（暗号化）/, wait: 30
    assert_equal 0, folder_upload_count
  end

  test "selecting more than the file limit rejects only the overflow" do
    paths = (1..31).map { |i| write_marking_png("n#{i}.png", frames: [ [ 20 + i, 30, 100, 80 ] ], seed: i) }
    pick(*paths)
    assert_selector "#device-upload-result", text: "失敗 1 件", wait: 120
    assert_selector "[data-failures] li", text: /1 回に選べるのは 30 ファイルまで/
    assert_equal 30, folder_upload_count
  end

  test "the existing dropdown still works" do
    upload = Upload.create!(user: users(:staff), sha256: "a" * 64, content_type: "image/jpeg", byte_size: 10, width: 10, height: 10, r2_key: "x")
    visit question_folder_path(@folder)
    find("select[aria-label='追加する画像']").find("option", text: "画像 ##{upload.id}").select_option
    click_on "画像を入れる"
    assert_selector "#folder_upload_#{upload.id}"
  end

  test "viewers do not see the file chooser" do
    visit question_folder_path(@folder) # staff で確認したあと、閲覧のみで入り直す
    click_on "ログアウト" rescue nil
    Capybara.reset_sessions!
    visit new_session_path
    fill_in "メールアドレス", with: users(:viewer).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    visit question_folder_path(@folder)
    assert_no_selector "#device-upload"
    assert_no_selector "#folder-files", visible: :all
  end
end
