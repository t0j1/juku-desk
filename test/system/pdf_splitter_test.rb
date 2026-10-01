require "application_system_test_case"

class PdfSplitterTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "upload a workbook, split into named files, rename and open the print page" do
    visit new_session_path
    fill_in "メールアドレス", with: users(:instructor).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    click_on "PDF分割"

    perform_enqueued_jobs do
      attach_file "file", file_fixture("workbook_p1.pdf")
      click_on "アップロードして解析"
      assert_text "自動判定: P1 前後分離型"
      click_on "この範囲で分割する"
    end
    assert_text "分割したファイル（10）"

    first_output = PdfSplitJob.last.outputs.first
    find_field("names[#{first_output.id}]").fill_in(with: "英語 第1回 問題")
    click_on "名前を保存"
    assert_text "ファイル名を更新しました。"
    assert_field "names[#{first_output.id}]", with: "英語 第1回 問題"

    click_on "印刷ページ（iPad用QR）"
    assert_selector "#qr svg"
    assert_text "英語 第1回 問題.pdf"
    assert_text "第1回 問題＋解答をまとめて印刷"
  end
end
