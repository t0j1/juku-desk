require "test_helper"

class DailyScheduleTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  setup do
    sign_in_as users(:staff)
    @station, = PrintStation.register!(name: "教室A")
    @day = Date.new(2026, 10, 5) # 月曜
  end

  def draft_params(**attrs)
    { name: "日報", execution_time: "18:00", repeat_type: "daily", execution_type: "create_draft", template_key: "daily_report", save_destination: "drafts", enabled: "1" }.merge(attrs)
  end

  def pdf_upload
    Rack::Test::UploadedFile.new(StringIO.new(PDF_BYTES), "application/pdf", original_filename: "a.pdf")
  end

  test "an invalid date is rejected with a message instead of silently showing today" do
    get daily_schedule_path(date: "2026-02-31")
    assert_redirected_to daily_schedule_path
    follow_redirect!
    assert_select "[role=alert], .alert-err, .flash", /日付の形式が正しくありません/
  end

  test "a blank date still shows today" do
    get daily_schedule_path
    assert_response :success
  end

  test "empty day shows the empty state and exactly one primary button" do
    get daily_schedule_path(date: @day.iso8601)
    assert_response :success
    assert_select "#timeline", /この日のタスクはありません/
    assert_select ".btn-primary", count: 1, text: "タスクを追加"
  end

  test "creates a draft task and the timeline shows the symbol and text pill, planned and actual times" do
    assert_difference -> { DailyScheduleTask.count }, 1 do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: draft_params }
    end
    task = DailyScheduleTask.last
    assert_redirected_to daily_schedule_path(date: @day.iso8601, task: task.id)
    task.run!(Time.zone.local(2026, 10, 5, 18, 0), now: Time.zone.local(2026, 10, 5, 18, 1))

    get daily_schedule_path(date: @day.iso8601, task: task.id)
    assert_select "#task_#{task.id}", /◐.*下書き保存済み/m
    assert_select "#task_#{task.id}", /予定 18:00/
    assert_select "#task_#{task.id}", /実際 18:01/
    assert_select "#task-detail", /送信・確定・公開は自動では行いません/
    assert_select "#task-detail", /直近の実行/
  end

  test "a slot with no record is shown as not run, never as success" do
    task = DailyScheduleTask.create!(draft_params)
    get daily_schedule_path(date: @day.iso8601)
    assert_select "#task_#{task.id}", /!.*未実行/m
    assert_select "#task_#{task.id}", { text: /実行済み/, count: 0 }
  end

  test "creates a print task with a PDF; rejects a missing PDF and a non-PDF" do
    base = { name: "朝", execution_time: "08:00", repeat_type: "weekdays", execution_type: "print", print_station_id: @station.id, copies: 2, duplex: "long", driver_preset: "トレイ2・両面・ホチキス" }
    assert_no_difference -> { DailyScheduleTask.count } do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: base }
      assert_response :unprocessable_entity
    end
    bad = Rack::Test::UploadedFile.new(StringIO.new("hello"), "application/pdf", original_filename: "x.pdf")
    assert_no_difference -> { DailyScheduleTask.count } do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: base.merge(pdf: bad) }
      assert_response :unprocessable_entity
      assert_select ".alert-err", /PDF ではありません/
    end
    assert_difference -> { DailyScheduleTask.count }, 1 do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: base.merge(pdf: pdf_upload) }
    end
    assert_equal [ 2, "long", "weekdays" ], DailyScheduleTask.last.then { |t| [ t.copies, t.duplex, t.repeat_type ] }
    assert_equal "トレイ2・両面・ホチキス", DailyScheduleTask.last.driver_preset
  end

  test "a free-typed tray name is refused and an existing value is kept on edit" do
    base = { name: "朝", execution_time: "08:00", repeat_type: "weekdays", execution_type: "print", print_station_id: @station.id, copies: 1, pdf: pdf_upload }
    assert_no_difference -> { DailyScheduleTask.count } do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: base.merge(driver_preset: "デフォルト") }
      assert_response :unprocessable_entity
    end
    task = DailyScheduleTask.create!(draft_params)
    task.update_columns(driver_preset: "bizhub-551i")
    patch daily_schedule_task_path(task), params: { date: @day.iso8601, daily_schedule_task: { name: "改名", driver_preset: "bizhub-551i" } }
    assert_equal "bizhub-551i", task.reload.driver_preset
  end

  test "toggle, duplicate and delete (with audit)" do
    task = DailyScheduleTask.create!(draft_params)
    post toggle_daily_schedule_task_path(task, date: @day.iso8601)
    refute task.reload.enabled
    assert_difference -> { DailyScheduleTask.count }, 1 do
      post duplicate_daily_schedule_task_path(task, date: @day.iso8601)
    end
    assert_equal "日報 のコピー", DailyScheduleTask.order(:id).last.name
    assert_difference -> { AuditLog.where(action: "delete").count }, 1 do
      assert_difference -> { DailyScheduleTask.count }, -1 do
        delete daily_schedule_task_path(task, date: @day.iso8601)
      end
    end
  end

  test "the delete button asks for confirmation" do
    task = DailyScheduleTask.create!(draft_params)
    get daily_schedule_path(date: @day.iso8601, task: task.id)
    assert_select "#task-detail button[data-turbo-confirm]"
  end

  test "a once-task whose time has passed can be saved and shows the notice" do
    post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: draft_params(repeat_type: "once", once_date: "2020-01-01") }
    task = DailyScheduleTask.last
    assert_equal Date.new(2020, 1, 1), task.once_date
    get daily_schedule_path(date: "2020-01-01", task: task.id, edit: task.id)
    assert_select ".alert-warn", /この時刻は過ぎています/
  end

  test "viewers cannot change tasks" do
    sign_in_as users(:viewer)
    assert_no_difference -> { DailyScheduleTask.count } do
      post daily_schedule_tasks_path, params: { date: @day.iso8601, daily_schedule_task: draft_params }
    end
  end

  test "the sidebar links to the daily schedule without SCHEDULE_WEB_URL" do
    get daily_schedule_path
    assert_select "#app-sidebar a[href='/schedule/daily'][aria-current='page']"
  end

  test "the date label opens a date picker that goes to the chosen day by the date param, and the arrows and today link stay" do
    get daily_schedule_path(date: "2026-10-05")
    assert_select "form#daily-date-form[method=get][action=?]", daily_schedule_path do
      assert_select "button#daily-date", /10\/5/
      assert_select "input[type=date][name=date][value=?]", "2026-10-05"
    end
    assert_select "a[aria-label='前の日'][href=?]", daily_schedule_path(date: "2026-10-04")
    assert_select "a[aria-label='次の日'][href=?]", daily_schedule_path(date: "2026-10-06")
    assert_select "a", text: "今日"
    get daily_schedule_path(date: "2026-12-29")
    assert_response :success
    assert_select "#daily-date", /12\/29/
  end
end
