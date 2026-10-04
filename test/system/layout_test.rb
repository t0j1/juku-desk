require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: users(:instructor).email_address
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

  # SCREENSHOTS=1 bin/rails test test/system/layout_test.rb で tmp/nav_shots/ に PR 用の画像を出す
  def shot(name)
    return unless ENV["SCREENSHOTS"]
    FileUtils.mkdir_p(Rails.root.join("tmp/nav_shots"))
    page.save_screenshot(Rails.root.join("tmp/nav_shots/#{name}.png").to_s)
  end

  test "the login screen has no sidebar" do
    visit new_session_path
    assert_selector "h1, h2, form"
    assert_no_selector "nav[aria-label='メインメニュー']", visible: :all
    assert_no_selector "#app-sidebar", visible: :all
  end

  test "the kiosk print screen has no sidebar" do
    job = create_pdf_job
    job.update!(status: :done)
    link = PrintLink.reissue!(by: users(:instructor))
    visit kiosk_print_path(token: link.token)
    assert_text "教材を印刷"
    assert_no_selector "#app-sidebar", visible: :all
  end

  test "after login every main screen shows the sidebar with the current screen highlighted" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    log_in
    {
      "生徒データベース" => students_path, "PDF分割" => tools_pdf_splitter_jobs_path,
      "印刷" => print_library_path, "小テスト作成" => new_quiz_path
    }.each do |label, path|
      visit path
      within "nav[aria-label='メインメニュー']" do
        assert_selector "a[aria-current='page']", count: 1
        assert_selector "a[aria-current='page']", text: label
      end
    end
  end

  test "the schedule group appears only when SCHEDULE_WEB_URL is set and opens in the same tab" do
    page.driver.browser.manage.window.resize_to(1024, 768)
    with_schedule_web_url(nil) do
      log_in
      assert_no_selector "nav[aria-label='メインメニュー'] a", text: "年間スケジュール"
    end
    with_schedule_web_url("https://sekigaku.example.pages.dev") do
      visit students_path
      link = find("nav[aria-label='メインメニュー'] a", text: "管理画面")
      assert_match %r{/schedule/admin\z}, link[:href]
      assert link[:target].blank?, "同じタブで開く"
      assert_selector "nav[aria-label='メインメニュー'] a", text: "年間スケジュール"
      assert_selector "nav[aria-label='メインメニュー'] a", text: "生徒ページ"
      shot "rails_1024_students"
    end
  end

  test "at 768px the sidebar is shown and the page does not scroll sideways" do
    page.driver.browser.manage.window.resize_to(768, 1024)
    log_in
    assert_selector "#app-sidebar", visible: true
    assert_no_selector "#sidebar-toggle", visible: true
    assert_equal false, page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")
    shot "rails_768"
  end

  test "below 768px the sidebar is collapsed and opens and closes with the menu button" do
    page.driver.browser.manage.window.resize_to(700, 1024)
    log_in
    assert_no_selector "#app-sidebar", visible: true
    shot "rails_700_closed"
    toggle = find("#sidebar-toggle")
    assert_equal "false", toggle[:"aria-expanded"]

    toggle.click
    assert_selector "#app-sidebar", visible: true
    assert_equal "true", find("#sidebar-toggle")[:"aria-expanded"]
    assert_selector "#app-sidebar a", text: "PDF分割"
    shot "rails_700_open"

    within("#app-sidebar") { click_on "閉じる" }
    assert_no_selector "#app-sidebar", visible: true
    assert_equal "false", find("#sidebar-toggle")[:"aria-expanded"]

    find("#sidebar-toggle").click
    assert_selector "#app-sidebar", visible: true
    page.driver.browser.action.move_to_location(650, 500).click.perform # サイドバーの外（スクリム）をタップ
    assert_no_selector "#app-sidebar", visible: true

    find("#sidebar-toggle").click
    find("body").send_keys(:escape)
    assert_no_selector "#app-sidebar", visible: true
  end
end
