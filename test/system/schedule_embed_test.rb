require "application_system_test_case"

# schedule-web を juku-desk のレイアウト（サイドバー）の本文に iframe で埋め込む画面
class ScheduleEmbedTest < ApplicationSystemTestCase
  BASE = "https://sekigaku.example.pages.dev".freeze
  PAGES = { "年間スケジュール" => [ "/schedule", "/" ], "管理画面" => [ "/schedule/admin", "/admin" ], "生徒ページ" => [ "/schedule/pickup", "/pickup" ] }.freeze

  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  def with_schedule_web_url(value)
    old = ENV["SCHEDULE_WEB_URL"]
    value.nil? ? ENV.delete("SCHEDULE_WEB_URL") : ENV["SCHEDULE_WEB_URL"] = value
    yield
  ensure
    old.nil? ? ENV.delete("SCHEDULE_WEB_URL") : ENV["SCHEDULE_WEB_URL"] = old
  end

  test "each page embeds schedule-web in an iframe and keeps the sidebar with the current item highlighted" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    with_schedule_web_url(BASE) do
      log_in
      PAGES.each do |label, (path, remote)|
        visit path
        assert_selector "#schedule-frame[src='#{BASE}#{remote}']"
        within "nav[aria-label='メインメニュー']" do
          assert_selector "a[aria-current='page']", count: 1
          assert_selector "a[aria-current='page']", text: label
        end
        assert_selector "#app-sidebar", visible: true
      end
    end
  end

  test "the iframe fills the content area without a second scrollbar" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    with_schedule_web_url(BASE) do
      log_in
      visit "/schedule/admin"
      assert_selector "#schedule-frame"
      assert_equal false, page.evaluate_script("document.documentElement.scrollHeight > window.innerHeight")
      assert_equal true, page.evaluate_script("document.getElementById('schedule-frame').getBoundingClientRect().height > 500")
    end
  end

  test "the sidebar link opens the embedded page in the same tab" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    with_schedule_web_url(BASE) do
      log_in
      click_on "管理画面"
      assert_current_path "/schedule/admin"
      assert_equal 1, page.driver.browser.window_handles.size
    end
  end

  test "without SCHEDULE_WEB_URL the page says it is not set instead of staying blank" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    with_schedule_web_url(nil) do
      log_in
      PAGES.each_value do |(path, _)|
        visit path
        assert_selector "#schedule-unset", text: "未設定"
        assert_no_selector "#schedule-frame"
        assert_selector "#app-sidebar", visible: true
      end
    end
  end
end
