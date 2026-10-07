require "application_system_test_case"

# 領域 0 件の画像を、チェックして一括でページ全体の構造化に積む（全部選ぶ／全部外す・件数表示）
class WholePageBulkTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    with_gemini(gemini_json)
    @folder = QuestionFolder.create!(name: "10月")
    @uploads = %w[a b c d].map do |seed|
      u = Upload.create!(user: users(:staff), sha256: seed * 64, content_type: "image/jpeg", byte_size: 12, width: 800, height: 600, r2_key: Upload.object_key(seed * 64, "image/jpeg"))
      path = File.join(@dir, "#{seed}.jpg")
      File.binwrite(path, "\xFF\xD8\xFF\xE0".b + seed)
      ImageStorage.put_file(u.r2_key, path, content_type: "image/jpeg")
      @folder.folder_uploads.create!(upload: u)
      u
    end
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    reset_gemini
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  test "the count follows the checkboxes, select none / all work, and running queues only the chosen" do
    visit question_folder_path(@folder)
    assert_selector "#extract-whole-submit", text: "4 枚を構造化"
    click_on "全部外す"
    assert_selector "#extract-whole-submit", text: "0 枚を構造化"
    assert_selector "#extract-whole-submit:disabled"
    check "whole_upload_#{@uploads.first.id}"
    check "whole_upload_#{@uploads.second.id}"
    assert_selector "#extract-whole-submit", text: "2 枚を構造化"
    click_on "全部選ぶ"
    uncheck "whole_upload_#{@uploads.last.id}"
    assert_selector "#extract-whole-submit", text: "3 枚を構造化"
    click_on "選んだ画像をページ全体で構造化する"
    assert_text "3 枚を順番待ちに入れました"
    assert_equal [ 1, 1, 1, 0 ], @uploads.map { |u| u.crop_regions.count }
    assert_selector "#whole-candidates li", count: 1 # 残りの 1 枚だけ
  end
end
