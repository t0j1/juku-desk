require "test_helper"

class PrintScheduleGroupTest < ActiveSupport::TestCase
  include PdfStorageTestHelper

  MONDAY = Date.new(2026, 10, 5)
  TUESDAY = MONDAY + 1

  setup do
    @station, = PrintStation.register!(name: "教室A")
    @group = PrintScheduleGroup.create!(name: "朝のセット", print_station: @station, weekdays: [ 1 ], start_time: "08:00", interval_minutes: 2)
    book = Wordbook.create!(name: "LEAP#{SecureRandom.hex(2)}").tap { |wb| 5.times { |i| wb.words.create!(number: i + 1, term: "t#{i}", meaning: "①m#{i}") } }
    @roster = PrintSchedule.create!(name: "名簿", kind: "roster", print_station: @station, weekdays: [ 1 ], time_of_day: "17:00", print_schedule_group: @group)
    @word = PrintSchedule.create!(name: "単語", kind: "word_test", print_station: @station, weekdays: [ 1 ], time_of_day: "17:00", print_schedule_group: @group,
                                  source_config: { "wordbook_id" => book.id, "start_no" => 1, "span" => 5 })
    @pdf = PrintSchedule.create_with_pdf!(data: PDF_BYTES, name: "固定", print_station: @station, weekdays: [ 1 ], time_of_day: "17:00", print_schedule_group: @group)
  end

  def times_for(date) = PrintJob.where(scheduled_for: date).order(:scheduled_at).map { |j| [ j.title, j.scheduled_at ] }

  test "a set of three jobs at 8:00 with a 2 minute gap is scheduled 8:00 / 8:02 / 8:04, in order" do
    result = PrintSchedule.generate_for!(MONDAY)
    assert_equal({ created: 3, skipped: 0 }, result)
    assert_equal [ [ "名簿", Time.zone.local(2026, 10, 5, 8, 0) ], [ "単語", Time.zone.local(2026, 10, 5, 8, 2) ], [ "固定", Time.zone.local(2026, 10, 5, 8, 4) ] ], times_for(MONDAY)
  end

  test "the gap is set on the group, and reordering changes who prints first" do
    @group.update!(interval_minutes: 5)
    @group.move!(@pdf, "up")
    @group.move!(@pdf, "up")
    PrintSchedule.generate_for!(MONDAY)
    assert_equal [ [ "固定", Time.zone.local(2026, 10, 5, 8, 0) ], [ "名簿", Time.zone.local(2026, 10, 5, 8, 5) ], [ "単語", Time.zone.local(2026, 10, 5, 8, 10) ] ], times_for(MONDAY)
  end

  test "no jobs on a day outside the group's weekdays, and none when the group is stopped" do
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(TUESDAY))
    @group.update!(active: false)
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(MONDAY))
  end

  test "generating twice on the same day does not duplicate" do
    PrintSchedule.generate_for!(MONDAY)
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(MONDAY))
    assert_equal 3, PrintJob.where(scheduled_for: MONDAY).count
  end

  test "jobs in a set count toward the daily limit; the rest are skipped" do
    result = PrintSchedule.generate_for!(MONDAY, limit: 2)
    assert_equal({ created: 2, skipped: 1 }, result)
    assert_equal [ "名簿", "単語" ], times_for(MONDAY).map(&:first)
    assert_equal 1, PrintSchedule.over_limit_on(MONDAY, limit: 2)
  end

  test "a schedule without a set keeps its own time and settings" do
    solo = PrintSchedule.create_with_pdf!(data: PDF_BYTES, name: "単独", print_station: @station, weekdays: [ 1 ], time_of_day: "09:30")
    PrintSchedule.generate_for!(MONDAY)
    assert_equal Time.zone.local(2026, 10, 5, 9, 30), solo.print_jobs.first.scheduled_at
  end

  test "members follow the group's station, weekdays and start time" do
    @group.update!(weekdays: [ 2 ], start_time: "10:00")
    assert_equal [ [ 2 ], "10:00" ], @roster.reload.then { |s| [ s.weekdays, s.time_of_day ] }
  end

  test "deleting a group keeps its schedules, now without a set" do
    @group.destroy!
    assert_nil @roster.reload.print_schedule_group_id
  end
end
