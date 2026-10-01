require "application_system_test_case"

class StudentsTest < ApplicationSystemTestCase
  test "instructor logs in and registers a student with weekdays" do
    visit new_session_path
    fill_in "メールアドレス", with: users(:instructor).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_text "生徒データベース"

    click_on "生徒を登録"
    assert_selector "h1", text: "生徒を登録"
    fill_in "氏名", with: "高橋 次郎"
    check "student_weekday_3"
    click_on "保存"
    assert_text "生徒を登録しました。"
    assert_text "水"
  end
end
