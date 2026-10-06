require "test_helper"

# 受入: 名簿・単語テストの PDF は貸し出し（lease）の直前にサーバーで生成される（仕様 §5 案A / §10-1〜6,12）。
# エージェントが取りに来る API を通して、次の 3 つの結果を確認する。
#   通常 → pending で作られ、lease 時に生成されて leased
#   名簿の対象 0 名 → 刷らず履歴にスキップ（cancelled）を残す
#   生成失敗（例外・雛形削除・単語なし）→ failed にして刷らない
class PrintApiGeneratedTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  TUESDAY = Date.new(2026, 10, 6)          # 火曜（fixtures の生徒は月・木のみなので、テスト毎に作り直す）
  LEASE_TIME = Time.zone.local(2026, 10, 6, 17, 1)

  setup do
    @station, @token = PrintStation.register!(name: "教室A")
    @auth = { "Authorization" => "Bearer #{@token}" }
    Student.destroy_all
  end

  def student(name, weekdays: [ 2 ])
    Student.create!(name: name).tap { |s| weekdays.each { |d| s.student_weekdays.create!(weekday: d) } }
  end

  def roster(source: {}, **attrs)
    PrintSchedule.create!(name: "名簿", kind: "roster", print_station: @station, weekdays: [ 2 ], time_of_day: "17:00",
                          source_config: source, **attrs)
  end

  def word_test(book, source: {}, **attrs)
    PrintSchedule.create!(name: "単語", kind: "word_test", print_station: @station, weekdays: [ 2 ], time_of_day: "17:00",
                          source_config: { "wordbook_id" => book.id, "start_no" => 1, "span" => 10 }.merge(source), **attrs)
  end

  def download(url) = get(url.sub("http://www.example.com", ""))

  # 生成器（Prawn）が例外を投げたときを再現する。ブロックの間だけ render_to を差し替え、必ず元に戻す
  def with_rendering_error
    klass = PrintSchedule::RosterPdf
    klass.class_eval do
      alias_method :render_to_without_error, :render_to
      define_method(:render_to) { |_path| raise "prawn boom" }
    end
    yield
  ensure
    klass.class_eval do
      alias_method :render_to, :render_to_without_error
      remove_method :render_to_without_error
    end
  end

  test "a roster job waits as pending without a PDF; the agent leases it and the generated PDF downloads" do
    student("山田")
    schedule = roster
    schedule.generate_job!(TUESDAY)

    job = PrintJob.last
    assert job.pending? # 通常 → pending（この時点では PDF を持たない）
    assert job.generate_on_lease
    assert_nil job.sha256

    travel_to(LEASE_TIME) do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :success
      leased = response.parsed_body["job"]
      assert_equal job.id.to_s, leased["id"]
      assert_equal "名簿", leased["title"]

      job.reload
      assert job.leased?
      refute job.generate_on_lease
      assert job.pdf_bytes.start_with?("%PDF")
      assert_equal Digest::SHA256.hexdigest(job.pdf_bytes), leased["sha256"]
      assert_equal job.pdf_bytes.bytesize, leased["byte_size"]

      download(leased["file_url"])
      assert_response :success
      assert_equal job.pdf_bytes, response.body.b
    end
  end

  test "a word_test job is generated at lease time and its copies stay as configured" do
    schedule = word_test(wordbooks(:small))
    schedule.generate_job!(TUESDAY)
    assert PrintJob.last.pending?

    travel_to(LEASE_TIME) do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :success
    end

    job = PrintJob.last
    assert job.leased?
    assert job.pdf_bytes.start_with?("%PDF")
    assert_equal schedule.copies, job.copies
  end

  test "an empty roster is not handed out; the history records the skip and the next job is still leased" do
    empty = roster # 対象日（火）に通う在籍生がいない＝0名
    empty.generate_job!(TUESDAY)
    other = PrintJob.create_with_pdf!(station: @station, title: "別のジョブ", data: PDF_BYTES, scheduled_at: LEASE_TIME - 30.seconds)

    travel_to(LEASE_TIME) do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :success
      assert_equal other.id.to_s, response.parsed_body.dig("job", "id") # 0名は飛ばして次を貸し出す
    end

    job = PrintJob.where(print_schedule: empty).first
    assert job.cancelled? # 0名はスキップ（失敗ではない）
    refute job.failed?
    assert_match(/対象 0 名のためスキップ/, job.result_message)
    assert_nil job.pdf_data
    refute job.lease_until
  end

  test "a word_test with no words is failed (not skipped) and is never handed out" do
    book = wordbook
    schedule = word_test(book)
    schedule.generate_job!(TUESDAY)
    book.destroy! # lease 直前に単語帳が消えた

    travel_to(LEASE_TIME) do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :no_content
    end

    job = PrintJob.last
    assert job.failed?
    assert_match(/対象が 0 件のため.*単語帳が無い/, job.result_message)
    assert_nil job.pdf_data
  end

  test "a generator error fails the job with the reason and is never handed out" do
    student("山田")
    schedule = roster
    schedule.generate_job!(TUESDAY)

    travel_to(LEASE_TIME) do
      with_rendering_error do
        get "/api/v1/print/jobs/next", headers: @auth
        assert_response :no_content
      end
    end

    job = PrintJob.last
    assert job.failed?
    assert_match(/PDF の生成に失敗しました/, job.result_message)
    assert_nil job.pdf_data
  end

  test "a schedule deleted before lease fails the job with the reason and is never handed out" do
    schedule = roster
    student("山田")
    schedule.generate_job!(TUESDAY)
    schedule.destroy!

    travel_to(LEASE_TIME) do
      get "/api/v1/print/jobs/next", headers: @auth
      assert_response :no_content
    end

    job = PrintJob.last
    assert job.failed?
    assert_match(/雛形が削除されたため/, job.result_message)
    assert_nil job.pdf_data
  end

  private
    def wordbook(count: 10)
      Wordbook.create!(name: "テスト帳#{SecureRandom.hex(2)}").tap do |wb|
        count.times { |i| wb.words.create!(number: i + 1, term: "term#{i + 1}", meaning: "①意味#{i + 1}") }
      end
    end
end
