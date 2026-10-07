require "application_system_test_case"

# 空の日: タスク/年間予定の2段表示と、年間スケジュールへのテキストリンク。日付ボタンは独立ボタンとして月カレンダーを開く
class DailyScheduleEmptyStateTest < ApplicationSystemTestCase
  setup do
    @env = ENV.to_h.slice("SUPABASE_URL", "SUPABASE_ANON_KEY", "SCHEDULE_WEB_URL")
    ENV["SUPABASE_URL"] = "https://example.supabase.co"
    ENV["SUPABASE_ANON_KEY"] = "anon-key"
    AnnualSchedule.transport = ->(_date) { [ 200, "[]" ] }
    page.driver.browser.manage.window.resize_to(1024, 800)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    AnnualSchedule.transport = nil
    %w[ SUPABASE_URL SUPABASE_ANON_KEY SCHEDULE_WEB_URL ].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
  end

  test "the date button is a standalone button that opens the month calendar, unlike the today button" do
    visit daily_schedule_path(date: "2026-10-07")
    button = find("#daily-date")
    assert_equal "44px", button.native.css_value("height")
    assert_equal "16px", button.native.css_value("font-size")
    assert_match(/10\/7/, button.text)
    assert_no_selector "[role=dialog]", visible: :visible
    button.click
    assert_selector "[role=dialog]", text: "2026年10月"
    assert_not_equal button.native.css_value("background-color"), find_link("今日").native.css_value("background-color")
  end

  test "an empty day shows two lines and the link opens the annual schedule" do
    visit daily_schedule_path(date: "2026-10-07")
    assert_selector "#empty-tasks", text: "タスク: なし"
    assert_selector "#empty-annual", text: "年間予定: この日は登録なし"
    assert_text "公開済みの予定だけ"
    assert_selector ".btn-primary", count: 1
    click_on "年間スケジュールを開く"
    assert_current_path schedule_path
  end
end
