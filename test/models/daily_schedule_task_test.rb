require "test_helper"

class DailyScheduleTaskTest < ActiveSupport::TestCase
  include PdfStorageTestHelper

  MONDAY = Date.new(2026, 10, 5)

  setup do
    @station, = PrintStation.register!(name: "教室A")
    @station.seen!("1.0", toner: "ok", paper: "ok")
  end

  def print_task(time: "08:00", repeat: "daily", **attrs)
    task = DailyScheduleTask.new(name: "朝の印刷", execution_time: time, repeat_type: repeat, execution_type: "print", print_station: @station, copies: 2, **attrs)
    task.attach_pdf(PDF_BYTES)
    task.save!
    task
  end

  def draft_task(**attrs)
    DailyScheduleTask.create!(name: "日報", execution_time: "18:00", repeat_type: "daily", execution_type: "create_draft", template_key: "daily_report", save_destination: "drafts", **attrs)
  end

  test "runs_on? follows the repeat type" do
    assert print_task.runs_on?(MONDAY)
    assert print_task(repeat: "weekdays").runs_on?(MONDAY)
    refute print_task(repeat: "weekdays").runs_on?(MONDAY + 5)
    custom = print_task(repeat: "custom", custom_weekdays: [ 1, 3 ])
    assert custom.runs_on?(MONDAY)
    refute custom.runs_on?(MONDAY + 1)
    once = print_task(repeat: "once", once_date: MONDAY)
    assert once.runs_on?(MONDAY)
    refute once.runs_on?(MONDAY + 1)
  end

  test "validates the fields of the chosen execution type" do
    refute DailyScheduleTask.new(name: "x", execution_time: "08:00", repeat_type: "daily", execution_type: "print").valid?
    refute DailyScheduleTask.new(name: "x", execution_time: "08:00", repeat_type: "daily", execution_type: "create_draft").valid?
    refute DailyScheduleTask.new(name: "x", execution_time: "8:00", repeat_type: "daily", execution_type: "create_draft", template_key: "notice", save_destination: "drafts").valid?
    refute DailyScheduleTask.new(name: "x", execution_time: "08:00", repeat_type: "custom", execution_type: "create_draft", template_key: "notice", save_destination: "drafts").valid?
    assert draft_task.valid?
  end

  test "a print run creates one PrintJob and records the planned and actual times separately" do
    task = print_task
    at = Time.zone.local(2026, 10, 5, 8, 0)
    now = at + 1.minute

    execution = assert_difference -> { PrintJob.count }, 1 do
      task.run!(at, now: now)
    end

    assert_equal "executed", execution.status
    assert_equal [ at, now ], [ execution.scheduled_at, execution.executed_at ]
    job = execution.print_job
    assert_equal [ "朝の印刷", 2, @station ], [ job.title, job.copies, job.print_station ]
  end

  test "an offline station is skipped, not shown as success, and not printed" do
    @station.update!(last_seen_at: 1.hour.ago)
    task = print_task
    at = Time.zone.local(2026, 10, 5, 8, 0)

    execution = assert_no_difference -> { PrintJob.count } do
      task.run!(at, now: at + 30.seconds)
    end

    assert_equal "skipped", execution.status
    assert_match(/オフライン/, execution.message)
  end

  test "an empty paper tray is skipped" do
    @station.seen!("1.0", toner: "ok", paper: "empty")
    at = Time.zone.local(2026, 10, 5, 8, 0)
    assert_equal "skipped", print_task.run!(at, now: at).status
  end

  test "a run that starts later than the grace period is recorded as not run" do
    task = print_task
    at = Time.zone.local(2026, 10, 5, 8, 0)

    execution = assert_no_difference -> { PrintJob.count } do
      task.run!(at, now: at + 11.minutes)
    end

    assert_equal "not_run", execution.status
  end

  test "a draft run saves a draft only" do
    task = draft_task
    at = Time.zone.local(2026, 10, 5, 18, 0)

    execution = task.run!(at, now: at)

    assert_equal "draft_saved", execution.status
    assert_match(/日報/, execution.draft_text)
    assert_match(/送信・確定はしていません/, execution.message)
  end

  test "the same planned time never runs twice" do
    task = draft_task
    at = Time.zone.local(2026, 10, 5, 18, 0)
    first = task.run!(at, now: at)

    second = nil
    assert_no_difference -> { DailyScheduleExecution.count } do
      second = task.run!(at, now: at + 1.minute)
    end
    assert_equal first, second
  end

  test "a failure is recorded as failed and not retried" do
    task = print_task
    task.update_columns(pdf_data: "not a pdf") # 壊れた PDF で PrintJob が作れない
    at = Time.zone.local(2026, 10, 5, 8, 0)

    execution = task.run!(at, now: at)

    assert_equal "failed", execution.status
    assert_match(/PDF/, execution.message)
    assert_equal 1, task.executions.count
  end
end
