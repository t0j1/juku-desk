require "application_system_test_case"

# マーキング機能の通し：アップロード → 領域の確定 → Gemini（モック）で構造化 → レビューで承認 → 小テストの作成 → 印刷プレビュー
class MarkingFlowTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    with_gemini(gemini_json)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  test "upload, confirm regions, structure with mocked Gemini, approve, build a quiz and open the print preview" do
    visit new_upload_path
    attach_file "marking-files", write_marking_png("flow.png", frames: [ [ 40, 50, 260, 150 ], [ 400, 60, 300, 180 ] ]), visible: :all
    assert_text "赤枠を 2 件検出しました"
    perform_enqueued_jobs do
      click_on "確定して保存"
      assert_text "保存しました（領域 2 件）"
    end
    assert_equal 2, @gemini.calls
    assert_equal 2, Question.count

    visit questions_path
    assert_selector "#questions tbody tr[id^='question_']", count: 2
    2.times do
      within(first("#questions tbody tr[id^='question_']", text: "未承認")) { click_on "承認" }
      assert_selector "#notice"
    end
    assert_selector "#questions tbody tr", text: "承認済み", count: 2

    visit new_marking_test_path
    fill_in "タイトル", with: "英語 通しテスト"
    select "ランダム", from: "出題方法"
    fill_in "問題数", with: 2
    click_on "小テストを作成"
    assert_selector "#test-items li", count: 2
    assert_no_selector "#shortfall"

    new_tab = window_opened_by { click_on "問題用を印刷" }
    within_window(new_tab) do
      assert_selector ".mt-item", count: 2
      assert_text "英語 通しテスト"
      assert_text "I (  ) a student."
    end
  end
end
