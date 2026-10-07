require "application_system_test_case"

# 1日のスケジュールで、時刻つきの年間予定がタスクと同じタイムラインに時刻順で並ぶ
class DailyScheduleAnnualTimelineTest < ApplicationSystemTestCase
  setup do
    @env = ENV.to_h.slice("SUPABASE_URL", "SUPABASE_ANON_KEY")
    ENV["SUPABASE_URL"] = "https://example.supabase.co"
    ENV["SUPABASE_ANON_KEY"] = "anon-key"
    DailyScheduleTask.create!(name: "朝の日報", execution_time: "08:00", repeat_type: "daily", execution_type: "create_draft", template_key: "daily_report", save_destination: "drafts", enabled: true)
    AnnualSchedule.transport = ->(_date) { [ 200, [ { type: "高2授業", title: "数学", start_time: "19:20:00", end_time: "22:00:00" }, { type: "休暇", title: "", start_time: nil, end_time: nil } ].to_json ] }
    ApprovedPickups.transport = ->(_date) { [ 200, [ { approved_time: "21:40:00", party_count: 3, max_capacity: 8, pickup_place: "駅前" } ].to_json ] }
    page.driver.browser.manage.window.resize_to(1024, 800)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    AnnualSchedule.transport = nil
    ApprovedPickups.transport = nil
    %w[ SUPABASE_URL SUPABASE_ANON_KEY ].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
  end

  test "the lesson sits in the timeline after the morning task, read-only, with the untimed holiday on top" do
    visit daily_schedule_path(date: "2026-01-05")
    rows = all("#timeline ol > li").map { |li| li.text }
    assert_match(/朝の日報/, rows.first)
    assert_match(/19:20〜22:00.*年間.*高2授業.*数学/m, rows[-2])
    assert_match(/送迎 21:40／乗車 3\/8/, rows.last)
    assert_selector "#annual-events", text: "休暇"
    assert_no_selector ".annual-timed a, .annual-timed button"
  end
end
