require "application_system_test_case"

class JobProgressTest < ApplicationSystemTestCase
  setup do
    @user = users(:staff)
    visit new_session_path
    fill_in "メールアドレス", with: @user.email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#app-sidebar" # ログインが済むのを待つ
  end

  test "modal shows percent and n/m, can be closed and reopened from the badge" do
    progress = JobProgress.create!(user: @user, kind: "dummy", title: "ダミー処理", status: :running, total: 10, done: 4, started_at: 30.seconds.ago)
    visit current_path # 処理中のものがあるページを読み直す

    assert_selector "[data-progress-target=badge]", text: "処理中"
    click_on "処理中"
    within "dialog" do
      assert_text "ダミー処理"
      assert_text "40%"
      assert_text "4 / 10 件"
      assert_text "残り約"
      assert_button "キャンセル"
      click_on "閉じる"
    end
    assert_no_selector "dialog[open]"
    assert_selector "[data-progress-target=badge]" # 閉じても処理中のバッジは残る

    progress.update_columns(done: 10, status: JobProgress.statuses[:succeeded], finished_at: Time.current)
    click_on "処理中"
    within("dialog") { assert_text "100%", wait: 8 }
  end

  test "cancel button asks the job to stop and the modal shows cancelled" do
    JobProgress.create!(user: @user, kind: "dummy", title: "ダミー処理", status: :running, total: 10, done: 2, started_at: 5.seconds.ago)
    visit current_path
    click_on "処理中"
    within "dialog" do
      click_on "キャンセル"
      assert_text "キャンセルしています"
    end
    progress = JobProgress.last
    assert progress.cancel_requested?
    progress.update_columns(status: JobProgress.statuses[:cancelled], finished_at: Time.current) # ジョブが次の区切りで止まった
    within("dialog") { assert_text "キャンセルしました", wait: 8 }
  end

  test "a queued job is removed from the queue by cancel and shows cancelled at once" do
    progress = JobProgress.enqueue(DummyProgressJob, 5, user: @user, kind: "dummy", title: "順番待ち処理")
    visit current_path
    click_on "処理中"
    within "dialog" do
      assert_text "順番待ちです"
      click_on "キャンセル"
      assert_text "キャンセルしました"
    end
    assert progress.reload.cancelled?
  end

  test "unknown total shows elapsed time instead of a percentage" do
    JobProgress.create!(user: @user, kind: "dummy", title: "件数不明の処理", status: :running, started_at: 65.seconds.ago)
    visit current_path
    click_on "処理中"
    within("dialog") { assert_text(/処理中（経過 1:0\d）/) }
  end
end
