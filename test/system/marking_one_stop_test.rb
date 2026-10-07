require "application_system_test_case"

# 1画面で、全問題を形式別に確認し、外した問題は含めず、未承認は承認して小テストを作る
class MarkingOneStopTest < ApplicationSystemTestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    page.driver.browser.manage.window.resize_to(1024, 800)
    regions = make_regions(5, status: :extracted)
    types = %w[translate_en_ja reorder passage reorder translate_en_ja]
    @qs = regions.each_with_index.map do |r, i|
      r.questions.create!(subject: "英語", question_type: types[i], question_text: "問題文#{i + 1}", answer_text: "答え#{i + 1}", answer_source: (i == 1 ? "ai" : "material"))
    end
    @folder = QuestionFolder.create!(name: "10月")
    @folder.folder_uploads.create!(upload: regions.first.upload)
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

  test "from the folder: preview by type, uncheck one, create and land on the print page with approvals recorded" do
    visit question_folder_path(@folder)
    find("#one-stop-link").click
    assert_selector "#one-stop-sections section", count: 3
    assert_selector ".ai-answer-mark", text: "AI作成の解答"
    uncheck "question_ids_#{@qs.last.id}"
    fill_in "title", with: "画像から一気に"
    click_on "作成して印刷へ"
    assert_selector "#print-toolbar"
    exam = Exam.order(:id).last
    assert_equal "画像から一気に", exam.title
    assert_equal @qs.first(4).map(&:id).sort, exam.items.map(&:question_id).sort
    assert_equal 4, Question.approved.count
    assert_not @qs.last.reload.approved?
  end
end
