require "application_system_test_case"

# 日付の表示から日を選ぶと、その日の 1日のスケジュールへ移る
class DailyScheduleDatePickerTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1024, 800)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  test "clicking the date button opens the in-app calendar and choosing a day moves there" do
    visit daily_schedule_path(date: "2026-10-05")
    assert_no_selector "[role=dialog][aria-label='日付を選ぶ']", visible: :visible
    find("#daily-date").click
    assert_selector "[role=dialog][aria-label='日付を選ぶ']", text: "2026年10月"
    find("[aria-label='次の月']").click
    find("[aria-label='次の月']").click
    assert_selector "[role=dialog]", text: "2026年12月"
    find("[aria-label='12月29日']").click
    assert_current_path daily_schedule_path(date: "2026-12-29")
    assert_selector "#daily-date", text: "12/29"
  end

  test "Escape closes the calendar" do
    visit daily_schedule_path(date: "2026-10-05")
    find("#daily-date").click
    assert_selector "[role=dialog]"
    find("[aria-label='10月5日']").send_keys(:escape)
    assert_no_selector "[role=dialog]", visible: :visible
  end
end
