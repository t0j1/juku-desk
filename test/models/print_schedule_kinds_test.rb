require "test_helper"

class PrintScheduleKindsTest < ActiveSupport::TestCase
  include PdfStorageTestHelper

  TUESDAY = Date.new(2026, 10, 6)
  MONDAY = Date.new(2026, 10, 5)

  setup do
    @station, = PrintStation.register!(name: "教室A")
    Student.destroy_all
  end

  def student(name, grade: "中1", weekdays: [ 2 ], enrolled_on: nil, left_on: nil)
    Student.create!(name: name, grade: grade, enrolled_on: enrolled_on, left_on: left_on).tap do |s|
      weekdays.each { |d| s.student_weekdays.create!(weekday: d) }
    end
  end

  def roster(weekdays: [ 2 ], source: {}, layout: {}, **attrs)
    PrintSchedule.create!(name: "名簿", kind: "roster", print_station: @station, weekdays: weekdays, time_of_day: "17:00",
                          source_config: source, layout_config: layout, **attrs)
  end

  def wordbook(count: 10)
    Wordbook.create!(name: "LEAP#{SecureRandom.hex(2)}").tap do |wb|
      count.times { |i| wb.words.create!(number: i + 1, term: "term#{i + 1}", meaning: "①意味#{i + 1}") }
    end
  end

  def word_test(book, source: {}, **attrs)
    PrintSchedule.create!(name: "単語", kind: "word_test", print_station: @station, weekdays: [ 2 ], time_of_day: "17:00",
                          source_config: { "wordbook_id" => book.id, "start_no" => 1, "span" => 10 }.merge(source), **attrs)
  end

  def page_count(data) = data.scan(%r{/Type /Page\b(?!s)}).size

  def pdf_of(document)
    Tempfile.create([ "t", ".pdf" ]) { |f| document.render_to(f.path); File.binread(f.path) }
  end

  # --- 種別とバリデーション ---

  test "existing rows default to fixed_pdf and need a PDF" do
    assert_equal "fixed_pdf", PrintSchedule.new.kind
    refute PrintSchedule.new(name: "x", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00").valid?
  end

  test "roster and word_test need no PDF, but their source is validated" do
    assert roster.persisted?
    refute PrintSchedule.new(name: "x", kind: "roster", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00", source_config: { "target" => "grades" }).valid?
    refute PrintSchedule.new(name: "x", kind: "word_test", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00", source_config: {}).valid?
    refute PrintSchedule.new(name: "x", kind: "bogus", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00").valid?
  end

  test "layout values outside the range are rejected; unspecified ones fall back to the defaults" do
    refute PrintSchedule.new(name: "x", kind: "roster", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00", layout_config: { "body_size" => 99 }).valid?
    values, errors = PrintSchedule::Layout.resolve("roster", { "body_size" => 12 })
    assert_empty errors
    assert_equal [ 12, 15, "A4" ], values.values_at("body_size", "margin_v", "paper")
  end

  test "roster_auto copies is only for rosters" do
    assert roster(copies_mode: "roster_auto").persisted?
    book = wordbook
    refute PrintSchedule.new(name: "x", kind: "word_test", print_station: @station, weekdays: [ 2 ], time_of_day: "08:00", copies_mode: "roster_auto",
                             source_config: { "wordbook_id" => book.id }).valid?
  end

  test "switching a fixed_pdf schedule to another kind releases the PDF" do
    s = PrintSchedule.create_with_pdf!(data: PDF_BYTES, print_station: @station, name: "固定", weekdays: [ 2 ], time_of_day: "08:00")
    s.update!(kind: "roster")
    assert_nil s.reload.pdf_data
    assert_nil s.sha256
  end

  # --- 名簿 ---

  test "the roster lists only enrolled students who attend on that weekday" do
    student("在籍火")
    student("月だけ", weekdays: [ 1 ])
    student("退塾済", left_on: MONDAY)
    student("未入塾", enrolled_on: TUESDAY + 1)
    student("当日退塾", left_on: TUESDAY)

    names = roster.build_document(TUESDAY).students.map(&:name)

    assert_equal %w[ 在籍火 当日退塾 ].sort, names.sort
  end

  test "a student whose leave date is entered this morning is not on the printed roster (generated at lease time)" do
    s = student("山田")
    roster.generate_job!(TUESDAY)
    s.update!(left_on: TUESDAY - 1) # 朝に退塾日を入れた
    job = nil
    travel_to(Time.zone.local(2026, 10, 6, 17, 1)) { job = PrintJob.lease_next_for!(@station) }

    assert_nil job # 0 名なので刷らない
    assert PrintJob.last.failed?
  end

  test "the roster can be narrowed by grade or by students, and sorted" do
    a = student("あ", grade: "中3")
    student("い", grade: "中1")
    c = student("う", grade: "中1")

    assert_equal %w[ い う ], roster(source: { "target" => "grades", "grades" => [ "中1" ] }).build_document(TUESDAY).students.map(&:name).sort
    assert_equal [ a.name ], roster(source: { "target" => "students", "student_ids" => [ a.id ] }).build_document(TUESDAY).students.map(&:name)
    assert_equal %w[ い う あ ], roster.build_document(TUESDAY).students.map(&:name)
    assert_includes roster(source: { "order" => "kana" }).build_document(TUESDAY).students.map(&:name), c.name
  end

  test "the roster PDF is made, and spills onto more pages when it does not fit" do
    30.times { |i| student("生徒#{i.to_s.rjust(2, "0")}") }
    small = pdf_of(roster.build_document(TUESDAY))
    assert small.start_with?("%PDF")
    big = pdf_of(roster(layout: { "rows_mode" => "manual", "rows_per_page" => 10 }).build_document(TUESDAY))
    assert_operator page_count(big), :>, page_count(small)
    assert_operator page_count(big), :>=, 3
  end

  # --- 単語テスト ---

  test "the word test only has the words of the chosen book and range" do
    book = wordbook(count: 20)
    other = wordbook(count: 5)
    doc = word_test(book, source: { "start_no" => 5, "span" => 3 }).build_document(TUESDAY)

    assert_equal [ 5, 6, 7 ], doc.words.map(&:number)
    assert(doc.words.all? { |w| w.wordbook_id == book.id })
    refute_includes doc.words.map(&:wordbook_id), other.id
  end

  test "random mode draws the given number without duplicates" do
    doc = word_test(wordbook(count: 20), source: { "question_mode" => "random", "count" => 7, "span" => 20 }).build_document(TUESDAY)
    assert_equal 7, doc.words.size
    assert_equal doc.words.size, doc.words.map(&:id).uniq.size
  end

  test "the word test PDF is made with answers on a separate page, below, or not at all" do
    book = wordbook
    separate = pdf_of(word_test(book, source: { "answers" => "separate" }).build_document(TUESDAY))
    none = pdf_of(word_test(book, source: { "answers" => "none" }).build_document(TUESDAY))
    assert_equal page_count(none) + 1, page_count(separate)
    assert pdf_of(word_test(book, source: { "answers" => "bottom" }).build_document(TUESDAY)).start_with?("%PDF")
  end

  # --- 生成のタイミング ---

  test "the job is created without a PDF, and the PDF is generated when the station leases it" do
    student("山田")
    schedule = roster
    assert_equal({ created: 1, skipped: 0 }, PrintSchedule.generate_for!(TUESDAY))
    job = PrintJob.last
    assert job.pending?
    assert job.generate_on_lease
    assert_nil job.sha256

    leased = travel_to(Time.zone.local(2026, 10, 6, 17, 1)) { PrintJob.lease_next_for!(@station) }

    assert_equal job, leased
    assert leased.leased?
    refute leased.generate_on_lease
    assert leased.pdf_bytes.start_with?("%PDF")
    assert_equal leased.byte_size, leased.pdf_bytes.bytesize
    assert_equal schedule, leased.print_schedule
  end

  test "roster_auto sets the copies from the number of students at lease time (max 99)" do
    3.times { |i| student("生徒#{i}") }
    roster(copies: 2, copies_mode: "roster_auto").generate_job!(TUESDAY)

    leased = travel_to(Time.zone.local(2026, 10, 6, 17, 1)) { PrintJob.lease_next_for!(@station) }

    assert_equal 6, leased.copies
  end

  test "an empty roster is not printed and is recorded as failed with the reason; the next job is still leased" do
    roster.generate_job!(TUESDAY)
    student_job = PrintJob.create_with_pdf!(station: @station, title: "別のジョブ", data: PDF_BYTES, scheduled_at: Time.zone.local(2026, 10, 6, 17, 0, 30))

    leased = travel_to(Time.zone.local(2026, 10, 6, 17, 1)) { PrintJob.lease_next_for!(@station) }

    empty = PrintJob.where(print_schedule: PrintSchedule.last).first
    assert empty.failed?
    assert_match(/0 件のため/, empty.result_message)
    assert_nil empty.pdf_data
    assert_equal student_job, leased
  end

  test "a generation failure fails the job with the reason and never prints an old PDF" do
    book = wordbook
    schedule = word_test(book)
    schedule.generate_job!(TUESDAY)
    book.destroy!

    leased = travel_to(Time.zone.local(2026, 10, 6, 17, 1)) { PrintJob.lease_next_for!(@station) }

    assert_nil leased
    job = PrintJob.last
    assert job.failed?
    assert_match(/印刷していません/, job.result_message)
    assert_nil job.pdf_data
  end

  test "generating twice for the same day makes one job; the daily limit applies to the new kinds" do
    student("山田")
    roster.generate_job!(TUESDAY)
    assert_no_difference -> { PrintJob.count } do
      assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(TUESDAY))
    end

    PrintJob.destroy_all
    word_test(wordbook)
    assert_equal({ created: 1, skipped: 1 }, PrintSchedule.generate_for!(TUESDAY, limit: 1))
  end

  test "a stopped schedule and a revoked station make no job (unchanged)" do
    s = roster
    s.update!(active: false)
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(TUESDAY))
    s.update!(active: true)
    @station.revoke!
    assert_equal({ created: 0, skipped: 0 }, PrintSchedule.generate_for!(TUESDAY))
  end

  test "fixed_pdf schedules still make a job with the PDF at creation" do
    PrintSchedule.create_with_pdf!(data: PDF_BYTES, print_station: @station, name: "固定", weekdays: [ 2 ], time_of_day: "08:00")
    PrintSchedule.generate_for!(TUESDAY)
    job = PrintJob.last
    refute job.generate_on_lease
    assert job.pdf_bytes.start_with?("%PDF")
  end
end
