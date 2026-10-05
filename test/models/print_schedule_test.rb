require "test_helper"

class PrintScheduleTest < ActiveSupport::TestCase
  include PdfStorageTestHelper

  MONDAY = Date.new(2026, 10, 5)
  TUESDAY = MONDAY + 1

  setup do
    @station, = PrintStation.register!(name: "教室A")
  end

  def make(name: "週テスト", weekdays: [ 1 ], time: "08:30", **attrs)
    PrintSchedule.create_with_pdf!(data: PDF_BYTES, print_station: @station, name: name, weekdays: weekdays, time_of_day: time, **attrs)
  end

  test "creates a pending job on the chosen weekday at the chosen time with the template's settings" do
    schedule = make(copies: 3, staple: "左上", driver_preset: "A4両面")

    result = PrintSchedule.generate_for!(MONDAY)

    assert_equal 1, result[:created]
    job = PrintJob.order(:id).last
    assert job.pending?
    assert_equal schedule, job.print_schedule
    assert_equal MONDAY, job.scheduled_for
    assert_equal Time.zone.local(2026, 10, 5, 8, 30), job.scheduled_at
    assert_equal [ "週テスト", 3, "左上", "A4両面", @station ], [ job.title, job.copies, job.staple, job.driver_preset, job.print_station ]
    assert job.pdf_bytes.start_with?("%PDF")
  end

  test "does nothing on other weekdays and for stopped schedules" do
    make
    stopped = make(name: "停止中", weekdays: [ 2 ])
    stopped.update!(active: false)
    assert_no_difference -> { PrintJob.count } do
      PrintSchedule.generate_for!(TUESDAY)
    end
  end

  test "a stopped schedule makes no job, and creates one again once re-enabled" do
    s = make
    s.update!(active: false)
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(MONDAY))
    s.update!(active: true)
    assert_equal({ created: 1, skipped: 0 }, PrintSchedule.generate_for!(MONDAY))
  end

  test "next_print_at is the next matching weekday and time after now; nil when stopped" do
    s = make(weekdays: [ 1, 3 ], time: "08:30") # 月・水 08:30
    zone = Time.zone
    assert_equal zone.local(2026, 10, 5, 8, 30), s.next_print_at(zone.local(2026, 10, 5, 8, 0))
    assert_equal zone.local(2026, 10, 7, 8, 30), s.next_print_at(zone.local(2026, 10, 5, 8, 30)) # 同時刻は過ぎた扱い
    assert_equal zone.local(2026, 10, 12, 8, 30), s.next_print_at(zone.local(2026, 10, 7, 9, 0))
    s.update!(active: false)
    assert_nil s.next_print_at(zone.local(2026, 10, 5, 8, 0))
  end

  test "running twice for the same day does not create a second job" do
    make
    PrintSchedule.generate_for!(MONDAY)
    assert_no_difference -> { PrintJob.count } do
      PrintSchedule.generate_for!(MONDAY)
    end
  end

  test "a concurrent insert for the same day is absorbed by the unique index" do
    schedule = make
    assert schedule.generate_job!(MONDAY)
    assert_not schedule.generate_job!(MONDAY)
    assert_equal 1, schedule.print_jobs.count
  end

  test "stops at the daily limit and counts the rest as skipped" do
    3.times { |i| make(name: "雛形#{i}") }
    result = PrintSchedule.generate_for!(MONDAY, limit: 2)
    assert_equal({ created: 2, skipped: 1 }, result)
    assert_equal 2, PrintJob.where(scheduled_for: MONDAY).count
    # 翌日に回すのではなく、その日の分は上限までで止まる。再実行しても超えない
    assert_equal({ created: 0, skipped: 1 }, PrintSchedule.generate_for!(MONDAY, limit: 2))
  end

  test "the default daily limit is 10" do
    assert_equal 10, PrintSchedule::DAILY_LIMIT
  end

  test "revoked stations get no jobs" do
    make
    @station.revoke!
    assert_no_difference -> { PrintJob.count } do
      PrintSchedule.generate_for!(MONDAY)
    end
  end

  test "deleting a schedule keeps the jobs it made" do
    schedule = make
    PrintSchedule.generate_for!(MONDAY)
    schedule.destroy!
    job = PrintJob.order(:id).last
    assert_nil job.reload.print_schedule_id
  end

  test "validates weekdays, time and the PDF" do
    assert_raises(ActiveRecord::RecordInvalid) { make(weekdays: []) }
    assert_raises(ActiveRecord::RecordInvalid) { make(time: "25:00") }
    assert_raises(ArgumentError) { PrintSchedule.create_with_pdf!(data: "not a pdf", print_station: @station, name: "x", weekdays: [ 1 ], time_of_day: "08:00") }
  end

  test "stores the PDF in R2 when enabled, a separate object per generated job, and removes the template's on destroy" do
    with_pdf_storage("r2") do |r2|
      schedule = make
      assert schedule.r2_key.present?
      PrintSchedule.generate_for!(MONDAY)
      job = PrintJob.order(:id).last
      assert_not_equal schedule.r2_key, job.r2_key
      stored = schedule.r2_key
      schedule.destroy!
      assert_not r2.objects.key?(stored)
    end
  end
end

class PrintScheduleJobTest < ActiveJob::TestCase
  include PdfStorageTestHelper

  test "generates tomorrow's jobs" do
    station, = PrintStation.register!(name: "教室A")
    tomorrow = Time.zone.tomorrow
    PrintSchedule.create_with_pdf!(data: PDF_BYTES, print_station: station, name: "毎日", weekdays: (0..6).to_a, time_of_day: "07:00")
    assert_difference -> { PrintJob.where(scheduled_for: tomorrow).count }, 1 do
      PrintScheduleJob.perform_now
    end
  end

  test "is scheduled daily in production" do
    entry = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "print_schedule")
    assert_equal "PrintScheduleJob", entry["class"]
  end
end
