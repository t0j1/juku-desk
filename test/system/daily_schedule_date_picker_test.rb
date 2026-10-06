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

  test "choosing a date moves to that day by the date param" do
    visit daily_schedule_path(date: "2026-10-05")
    page.execute_script("const i = document.querySelector('#daily-date-form input[type=date]'); i.value = '2026-12-29'; i.dispatchEvent(new Event('change', { bubbles: true }))")
    assert_current_path daily_schedule_path(date: "2026-12-29")
    assert_selector "#daily-date", text: "12/29"
  end
end
