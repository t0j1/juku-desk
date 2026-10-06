require "test_helper"

class AdminPrintScheduleKindsTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  setup do
    sign_in_as users(:system_admin)
    @station, = PrintStation.register!(name: "教室A")
    @book = Wordbook.create!(name: "テスト帳").tap { |b| 5.times { |i| b.words.create!(number: i + 1, term: "w#{i}", meaning: "①m#{i}") } }
  end

  def base(**attrs)
    { name: "名簿", print_station_id: @station.id, copies: 1, weekdays: %w[ 2 ], time_of_day: "17:00" }.merge(attrs)
  end

  def pdf_upload = Rack::Test::UploadedFile.new(StringIO.new(PDF_BYTES), "application/pdf", original_filename: "a.pdf")

  test "the form has the three kind cards and a section per kind (only the chosen kind's fields are shown)" do
    get new_admin_print_schedule_path
    assert_response :success
    assert_select "[role=radiogroup] input[name='print_schedule[kind]']", count: 3
    assert_select "[data-exec-type-target=section][data-type=fixed_pdf]", 1
    assert_select "[data-exec-type-target=section][data-type=roster]", 2 # 名簿のデータソース＋部数の決め方
    assert_select "[data-exec-type-target=section][data-type=word_test]", 1
    assert_select "#layout_roster summary", /A4 縦・余白15mm・本文11pt/
  end

  test "creates a roster schedule without a PDF, saving only the changed layout values" do
    assert_difference -> { PrintSchedule.count }, 1 do
      post admin_print_schedules_path, params: { print_schedule: base(kind: "roster", copies_mode: "roster_auto",
        roster_source: { target: "grades", grades: %w[ 中1 ], order: "kana", attendance_box: "1", note_box: "0" },
        layout: { paper: "B5", body_size: "12", margin_v: "15", rules: "0" }) }
    end
    s = PrintSchedule.last
    assert_redirected_to admin_print_schedules_path
    assert_equal [ "roster", "roster_auto", nil ], [ s.kind, s.copies_mode, s.sha256 ]
    assert_equal({ "target" => "grades", "grades" => [ "中1" ], "student_ids" => [], "order" => "kana", "attendance_box" => true, "note_box" => false }, s.source_config)
    assert_equal({ "paper" => "B5", "body_size" => 12, "rules" => false }, s.layout_config)
  end

  test "creates a word test schedule; a missing wordbook is rejected with the reason" do
    post admin_print_schedules_path, params: { print_schedule: base(kind: "word_test", name: "単語", word_test_source: { wordbook_id: "" }) }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /単語帳を選んでください/
    assert_difference -> { PrintSchedule.count }, 1 do
      post admin_print_schedules_path, params: { print_schedule: base(kind: "word_test", name: "単語",
        word_test_source: { wordbook_id: @book.id, start_no: "2", span: "3", direction: "ja_en", question_mode: "random", count: "2", answers: "bottom" }) }
    end
    assert_equal [ @book.id, 2, 3, "ja_en", "random", 2, "bottom" ], PrintSchedule.last.source_config.values_at("wordbook_id", "start_no", "span", "direction", "question_mode", "count", "answers")
  end

  test "a fixed_pdf schedule still needs a PDF; out-of-range layout is rejected" do
    post admin_print_schedules_path, params: { print_schedule: base(kind: "fixed_pdf") }
    assert_response :unprocessable_entity
    post admin_print_schedules_path, params: { print_schedule: base(kind: "roster", layout: { body_size: "99" }) }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /本文の文字サイズ/
  end

  test "edit can replace the PDF of a fixed schedule, and changing the kind releases it" do
    post admin_print_schedules_path, params: { print_schedule: base(kind: "fixed_pdf", pdf: pdf_upload) }
    s = PrintSchedule.last
    old = s.sha256
    new_pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\nreplaced\n%%EOF\n"), "application/pdf", original_filename: "b.pdf")
    patch admin_print_schedule_path(s), params: { print_schedule: base(kind: "fixed_pdf", pdf: new_pdf) }
    assert_redirected_to admin_print_schedules_path
    refute_equal old, s.reload.sha256

    patch admin_print_schedule_path(s), params: { print_schedule: base(kind: "roster", roster_source: { target: "all" }) }
    assert_redirected_to admin_print_schedules_path
    s.reload
    assert_equal "roster", s.kind
    assert_nil s.pdf_data
  end

  test "the list shows the kind with a symbol and text, and a one-line data source" do
    PrintSchedule.create!(name: "名簿", kind: "roster", print_station: @station, weekdays: [ 2 ], time_of_day: "17:00")
    PrintSchedule.create!(name: "単語", kind: "word_test", print_station: @station, weekdays: [ 2 ], time_of_day: "17:00", source_config: { "wordbook_id" => @book.id, "start_no" => 1, "span" => 5 })
    get admin_print_schedules_path
    assert_select "#print_schedules", /☰.*日次出席名簿/m
    assert_select "#print_schedules", /A.*単語テスト/m
    assert_select "#print_schedules", /在籍×火・全員/
    assert_select "#print_schedules", /テスト帳 No\.1–5・英→日/
  end

  test "preview returns a sample PDF without saving, and rejects fixed_pdf" do
    assert_no_difference -> { PrintSchedule.count } do
      assert_no_difference -> { PrintJob.count } do
        post preview_admin_print_schedules_path, params: { print_schedule: { kind: "roster", layout: { body_size: "12" } } }
      end
    end
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
    post preview_admin_print_schedules_path, params: { print_schedule: { kind: "fixed_pdf" } }
    assert_response :unprocessable_entity
  end

  test "only system_admin can preview" do
    sign_in_as users(:staff)
    post preview_admin_print_schedules_path, params: { print_schedule: { kind: "roster" } }
    assert_redirected_to root_path
  end
end
