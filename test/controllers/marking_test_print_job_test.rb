require "test_helper"

class MarkingTestPrintJobTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:system_admin)
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    @station, = PrintStation.register!(name: "教室A")
    @station.seen!("1.0")
  end

  teardown do
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def make_q(**attrs)
    region = make_regions(1, status: :extracted).first
    region.questions.create!({ subject: "英語", question_text: "次の文を訳しなさい。", answer_text: "答え", explanation: "解説です", reviewed_at: Time.current, tags: %w[文法] }.merge(attrs))
  end

  def make_exam(**qattrs)
    5.times { |i| make_q(question_text: "問題#{i + 1} 次の漢字の読みを書きなさい。", **qattrs) }
    post marking_tests_path, params: { marking_test: { title: "第1回 小テスト", mode: "random", count: 5 } }
    Exam.order(:id).last
  end

  def create_job(exam, **params)
    post print_job_marking_test_path(exam), params: { print_job: { print_station_id: @station.id, copies: 2, driver_preset: "A4両面" }.merge(params) }
  end

  test "one action turns the quiz into a pending print job with a real PDF" do
    exam = make_exam

    assert_difference -> { PrintJob.count }, 1 do
      create_job(exam)
    end

    assert_redirected_to admin_print_jobs_path
    job = PrintJob.order(:id).last
    assert job.pending?
    assert_equal @station, job.print_station
    assert_equal 2, job.copies
    assert_equal "A4両面", job.driver_preset
    assert_equal "第1回 小テスト（問題用）", job.title
    assert job.pdf_bytes.start_with?("%PDF")
    text = PDF::Reader.new(StringIO.new(job.pdf_bytes)).pages.map(&:text).join
    assert_includes text, "第1回 小テスト"
    assert_equal 1, PDF::Reader.new(StringIO.new(job.pdf_bytes)).page_count
  end

  test "the answer sheet has its own title and the answers" do
    exam = make_exam
    post print_job_marking_test_path(exam), params: { kind: "answer", print_job: { print_station_id: @station.id } }
    job = PrintJob.order(:id).last
    assert_equal "第1回 小テスト（解答用）", job.title
    assert_includes PDF::Reader.new(StringIO.new(job.pdf_bytes)).pages.map(&:text).join, "答え"
  end

  test "the job is leased by the agent the same way as an uploaded one" do
    create_job(make_exam)
    leased = PrintJob.lease_next_for!(@station)
    assert leased.leased?
  end

  test "an offline station gets no job" do
    @station.update_columns(last_seen_at: 1.hour.ago)
    exam = make_exam
    assert_no_difference -> { PrintJob.count } do
      create_job(exam)
    end
    assert_redirected_to print_marking_test_path(exam, kind: "question")
    assert_match "オフライン", flash[:alert]
  end

  test "math is typeset in the PDF, never printed as LaTeX source (question and answer sheets)" do
    exam = make_exam(question_text: 'cos を求めなさい。$\\cos^2 x$ と $\\frac{\\sqrt{3}}{2}$', answer_text: '$-\\sqrt{3}$、$\\frac{7}{6}\\pi$、$x^2$', explanation: '$\\frac{1}{2}$')
    create_job(exam)
    post print_job_marking_test_path(exam), params: { kind: "answer", print_job: { print_station_id: @station.id } }
    PrintJob.order(:id).last(2).each do |job|
      text = PDF::Reader.new(StringIO.new(job.pdf_bytes)).pages.map(&:text).join
      assert_no_match(/\\|\$|\^|frac|sqrt|\{/, text, job.title)
    end
    sheet = PDF::Reader.new(StringIO.new(PrintJob.order(:id).last.pdf_bytes)).pages.map(&:text).join
    assert_includes sheet, "√3"
    assert_includes sheet, "7/6π"
  end

  test "a quiz with a formula that cannot be typeset gets no job and an error" do
    exam = make_exam(question_text: 'x を求めなさい。$\\begin{cases} x \\end{cases}$')
    assert_no_difference -> { PrintJob.count } do
      create_job(exam)
    end
    assert_match "数式", flash[:alert]
  end

  test "a failure while writing the PDF creates no job" do
    exam = make_exam
    original = Marking::ExamPdf.instance_method(:render_to)
    Marking::ExamPdf.define_method(:render_to) { |_| raise Marking::ExamPdf::Unsupported, "PDF を作れませんでした" }
    assert_no_difference -> { PrintJob.count } do
      create_job(exam)
    end
    assert_match "作れませんでした", flash[:alert]
  ensure
    Marking::ExamPdf.define_method(:render_to, original)
  end

  test "a missing or revoked station is refused" do
    exam = make_exam
    @station.revoke!
    assert_no_difference -> { PrintJob.count } do
      create_job(exam)
    end
    assert_match "ステーション", flash[:alert]
  end

  test "only system admins can create the job" do
    exam = make_exam
    sign_out
    sign_in_as users(:staff)
    assert_no_difference -> { PrintJob.count } do
      create_job(exam)
    end
    assert_redirected_to root_path
  end

  test "the print screen shows the form to admins only when a station exists" do
    exam = make_exam
    get print_marking_test_path(exam)
    assert_select "form[action=?]", print_job_marking_test_path(exam)
  end
end
