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
      attach_file "file", file_fixture("workbook_p1.pdf"), make_visible: true
      click_on "アップロードして解析"
      assert_text "自動判定: P1 前後分離型"
      visit current_path # 解析中の自動更新（meta refresh）と押下が重ならないよう読み直す
      within("#boundaries-form") { click_on "この範囲で分割する" }
    end
    assert_text "分割したファイル（10）"

    first_output = PdfSplitJob.last.outputs.first
    find_field("names[#{first_output.id}]").fill_in(with: "英語 第1回 問題")
    click_on "名前を保存"
    assert_text "ファイル名を更新しました。"
    assert_field "names[#{first_output.id}]", with: "英語 第1回 問題"

    click_on "印刷ページ（iPad用QR）"
    assert_selector "#qr svg"
    visit current_path # 分割中の画面の自動更新（meta refresh）が残らないよう読み直す
    find("summary", text: "ファイルごとに印刷・保存する").click
    assert_text "英語 第1回 問題.pdf"
    assert_selector "#print-queue [data-print-queue-target=empty]", text: "リストに追加"

    # 印刷リスト: 第2回(問題のみ) → 第1回(問題と解答) の順に追加し、並べ替え・削除・再読み込み後も残る
    within("#round-list tr[data-round='第2回']") do
      find("select").find("option", text: "問題のみ").select_option
      click_on "＋ リストに追加"
    end
    within("#round-list tr[data-round='第1回']") { click_on "＋ リストに追加" }
    within("#print-queue") do
      assert_text "1. 第2回 問題のみ"
      assert_text "2. 第1回 問題と解答"
      assert_text "2 / 4回分"
      within("li[data-index='1']") { click_on "↑" }
      assert_text "1. 第1回 問題と解答"
    end
    visit current_path
    within("#print-queue") do
      assert_text "1. 第1回 問題と解答"
      assert_equal %w[第1回:both 第2回:problem], all("input[name='items[]']", visible: false).map(&:value)
      within("li[data-index='0']") { click_on "削除" }
      assert_text "1. 第2回 問題のみ"
      click_on "リストを空にする"
      assert_text "リストに追加"
    end
  end

  test "add a problem/answer pair row and split a scanned PDF" do
    job = create_pdf_job(fixture: "scanned_images.pdf")
    job.update!(boundaries: [])
    visit new_session_path
    fill_in "メールアドレス", with: users(:instructor).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_link "PDF分割"
    visit tools_pdf_splitter_job_path(job)

    find("[aria-label=\'1組目 問題 開始\']").fill_in(with: 2)
    find("[aria-label=\'1組目 問題 終了\']").fill_in(with: 4)
    find("[aria-label=\'1組目 解答 開始\']").fill_in(with: 8)
    find("[aria-label=\'1組目 解答 終了\']").fill_in(with: 9)
    click_on "＋ 回を追加（問題と解答）"
    assert_equal "第2回", find("[aria-label='2組目 回']").value
        find("[aria-label=\'2組目 問題 開始\']").fill_in(with: 5)
    find("[aria-label=\'2組目 問題 終了\']").fill_in(with: 7)
    find("[aria-label=\'2組目 解答 開始\']").fill_in(with: 10)
    find("[aria-label=\'2組目 解答 終了\']").fill_in(with: 12)
    perform_enqueued_jobs { find("#split-pairs").click }
    assert_text "分割したファイル（4）"
    assert_equal %w[第1回_問題 第2回_問題 第1回_解答 第2回_解答], job.outputs.reload.map(&:display_name)
  end
end
