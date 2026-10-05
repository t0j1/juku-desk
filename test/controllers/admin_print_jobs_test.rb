require "test_helper"

class AdminPrintJobsTest < ActionDispatch::IntegrationTest
  include PdfStorageTestHelper

  setup do
    sign_in_as users(:system_admin)
    @station, = PrintStation.register!(name: "教室A")
    @pdf_job = users(:system_admin).pdf_split_jobs.create!(original_filename: "book.pdf", page_count: 4)
    @output = @pdf_job.outputs.create!(display_name: "第3回小テスト", page_from: 1, page_to: 2, position: 1)
  end

  # 実際の PDF の切り出しには qpdf が要るので、PDF を書き出す部分だけ差し替える
  def with_fake_builder
    original = PdfSplitter::Builder.method(:with_file)
    PdfSplitter::Builder.define_singleton_method(:with_file) do |_output, &blk|
      Tempfile.create([ "out", ".pdf" ]) { |f| f.binmode; f.write(PdfStorageTestHelper::PDF_BYTES); f.flush; blk.call(f.path) }
    end
    yield
  ensure
    PdfSplitter::Builder.define_singleton_method(:with_file, original)
  end

  def new_job(**attrs)
    PrintJob.create_with_pdf!(station: @station, title: "x", data: PDF_BYTES, **attrs)
  end

  test "the index explains how to print a quiz (save the preview as PDF, upload it, create the job)" do
    get admin_print_jobs_path
    assert_response :success
    assert_select "#print-help", text: /印刷プレビューで「PDF として保存」.*アップロード.*印刷ジョブを作成・実行.*自動生成.*当面/m
  end

  test "staple choices are none / upper-left only, and jobs saved with an old value still list" do
    assert_equal %w[ なし 左上 ], PrintJobsHelper::STAPLES
    new_job(staple: "右上")
    new_job(staple: "2か所")
    get admin_print_jobs_path
    assert_response :success
    assert_select "p.caption", /ホチキス右上/
    assert_select "p.caption", /ホチキス2か所/
    get new_admin_print_job_path
    assert_select "select[name='print_job[staple]'] option", count: 2
  end

  test "create takes the duplex choice; blank means driver default; the new form offers it" do
    get new_admin_print_job_path
    assert_select "select[name='print_job[duplex]'] option", count: 3
    with_fake_builder do
      post admin_print_jobs_path, params: { print_job: { output_id: @output.id, print_station_id: @station.id, scheduled_at: "2026-10-06T07:30", copies: "1", duplex: "short" } }
      assert_equal "short", PrintJob.last.duplex
      post admin_print_jobs_path, params: { print_job: { output_id: @output.id, print_station_id: @station.id, scheduled_at: "2026-10-06T07:30", copies: "1", duplex: "" } }
      assert_nil PrintJob.last.duplex
    end
  end

  test "an invalid duplex value is refused by the model" do
    job = PrintJob.new(print_station: @station, title: "x", duplex: "both")
    assert_not job.valid?
    assert job.errors[:duplex].any?
    assert_nil new_job(duplex: "").duplex
  end

  test "the agent job json carries duplex (null when unspecified)" do
    assert_equal "long", new_job(duplex: "long").as_agent_json(base_url: "http://x")[:duplex]
    json = new_job.as_agent_json(base_url: "http://x")
    assert json.key?(:duplex) && json[:duplex].nil?
  end

  test "only system_admin can use it" do
    [ users(:staff), users(:viewer) ].each do |u|
      sign_in_as u
      get admin_print_jobs_path
      assert_redirected_to root_path
      get new_admin_print_job_path
      assert_redirected_to root_path
    end
  end

  test "create makes a pending job from a split output with the print settings, and is audited" do
    with_fake_builder do
      assert_difference -> { PrintJob.count }, 1 do
        assert_difference -> { AuditLog.where(action: "create", auditable_type: "PrintJob").count }, 1 do
          post admin_print_jobs_path, params: { print_job: { output_id: @output.id, print_station_id: @station.id, scheduled_at: "2026-10-06T07:30", expires_at: "",
                                                              copies: "5", collate: "1", staple: "左上", driver_preset: "A4両面・左上ホチキス" } }
        end
      end
    end
    assert_redirected_to admin_print_jobs_path
    job = PrintJob.last
    assert_equal [ "第3回小テスト", 5, true, "左上", "A4両面・左上ホチキス", "pending" ], [ job.title, job.copies, job.collate, job.staple, job.driver_preset, job.status ]
    assert_equal job.scheduled_at + 2.hours, job.expires_at
    assert_equal users(:system_admin), job.created_by
    assert_equal Digest::SHA256.hexdigest(PDF_BYTES), job.sha256
  end

  test "create without a pdf or a station, or with a deadline before the schedule, is refused" do
    with_fake_builder do
      assert_no_difference -> { PrintJob.count } do
        post admin_print_jobs_path, params: { print_job: { output_id: "", print_station_id: @station.id } }
        assert_response :unprocessable_entity
        post admin_print_jobs_path, params: { print_job: { output_id: @output.id, print_station_id: "" } }
        assert_response :unprocessable_entity
        post admin_print_jobs_path, params: { print_job: { output_id: @output.id, print_station_id: @station.id, scheduled_at: "2026-10-06T07:30", expires_at: "2026-10-06T07:00", copies: "1" } }
        assert_response :unprocessable_entity
        assert_select "#error_explanation", /締め切り|予定/
      end
    end
  end

  test "someone else's output cannot be printed" do
    other = users(:staff).pdf_split_jobs.create!(original_filename: "o.pdf", page_count: 1).outputs.create!(display_name: "他人", page_from: 1, page_to: 1, position: 1)
    with_fake_builder do
      assert_no_difference -> { PrintJob.count } do
        post admin_print_jobs_path, params: { print_job: { output_id: other.id, print_station_id: @station.id } }
      end
    end
    assert_response :unprocessable_entity
  end

  test "index shows status, the failure message, and the banners" do
    ok = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:acknowledged], finished_at: Time.current) }
    failed = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:failed], result_message: "用紙切れ", finished_at: Time.current) }
    waiting = new_job(scheduled_at: 1.minute.ago)
    get admin_print_jobs_path
    assert_select "#print_job_#{ok.id}", /印刷済み/
    assert_select "#print_job_#{failed.id}", /失敗.*用紙切れ/m
    assert_select "#print_job_#{waiting.id}", /待機中/
    assert_select "#problem-banner", /1 件/
    assert_select "#offline-banner", /教室A/
    @station.seen!("0.1.0")
    get admin_print_jobs_path
    assert_select "#offline-banner", false
  end

  test "an overdue pending job warns, a future one does not, and failures show the reason (last_error)" do
    overdue = new_job(scheduled_at: 30.minutes.ago)
    future = new_job(scheduled_at: 1.hour.from_now)
    failed = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:failed], result_message: "用紙切れ", finished_at: Time.current) }
    expired = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:expired], result_message: "締め切りを過ぎたため印刷していません", finished_at: Time.current) }
    silent = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:failed], result_message: nil, finished_at: Time.current) }
    done = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:acknowledged], finished_at: Time.current) }

    get admin_print_jobs_path
    assert_response :success
    assert_select "#overdue-banner", /1 件/
    assert_select "#print_job_overdue_#{overdue.id}", /予定時刻を過ぎても印刷されていません/
    assert_select "#print_job_overdue_#{future.id}", false
    assert_select "#print_job_overdue_#{done.id}", false
    assert_select "#print_job_error_#{failed.id}", /用紙切れ/
    assert_select "#print_job_error_#{expired.id}", /締め切りを過ぎたため印刷していません/
    assert_select "#print_job_error_#{silent.id}", /理由は記録されていません/
    assert_select "#print_job_error_#{done.id}", false
  end

  test "print now makes a pending future job due and extends a past deadline; others are refused" do
    future = new_job(scheduled_at: 1.day.from_now)
    post print_now_admin_print_job_path(future)
    assert_redirected_to admin_print_jobs_path
    future.reload
    assert_in_delta Time.current.to_i, future.scheduled_at.to_i, 5
    assert future.expires_at > future.scheduled_at
    assert_equal future, PrintJob.lease_next_for!(@station)

    done = new_job.tap { |j| j.update_columns(status: PrintJob.statuses[:acknowledged]) }
    post print_now_admin_print_job_path(done)
    assert_equal "待機中のジョブだけ「今すぐ印刷」できます。", flash[:alert]
  end

  test "cancel stops a pending job and the agent no longer gets it" do
    job = new_job(scheduled_at: 1.minute.ago)
    post cancel_admin_print_job_path(job)
    assert job.reload.cancelled?
    assert_nil PrintJob.lease_next_for!(@station)
    post cancel_admin_print_job_path(job)
    assert_equal "このジョブはすでに終わっています。", flash[:alert]
  end

  test "new form lists outputs and stations; with no station it asks to register one" do
    get new_admin_print_job_path
    assert_select "select#print_job_output_id option", /第3回小テスト/
    assert_select "select#print_job_print_station_id option", /教室A/
    @station.revoke!
    get new_admin_print_job_path
    assert_select "a", /印刷ステーションを登録/
  end

  test "an uploaded pdf (e.g. a saved quiz preview) becomes a job, titled by the file name" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PDF_BYTES), "application/pdf", original_filename: "第5回小テスト.pdf")
    assert_difference -> { PrintJob.count }, 1 do
      post admin_print_jobs_path, params: { print_job: { pdf: file, print_station_id: @station.id, copies: "10", collate: "1" } }
    end
    assert_redirected_to admin_print_jobs_path
    job = PrintJob.last
    assert_equal [ "第5回小テスト", 10, Digest::SHA256.hexdigest(PDF_BYTES) ], [ job.title, job.copies, job.sha256 ]
  end

  test "an uploaded file that is not a pdf is refused" do
    file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "application/pdf", original_filename: "x.pdf")
    assert_no_difference -> { PrintJob.count } do
      post admin_print_jobs_path, params: { print_job: { pdf: file, print_station_id: @station.id } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /PDF/
  end

  test "the red banner links to a failures-only view" do
    ok = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:acknowledged], finished_at: Time.current) }
    bad = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:failed], finished_at: Time.current) }
    get admin_print_jobs_path
    assert_select "#problem-banner a[href=?]", admin_print_jobs_path(problems: 1)
    get admin_print_jobs_path(problems: 1)
    assert_select "#print_job_#{bad.id}"
    assert_select "#print_job_#{ok.id}", false
  end

  test "the filter links narrow the list to failures, expirations and overdue jobs" do
    ok = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:acknowledged], finished_at: Time.current) }
    failed = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:failed], result_message: "用紙切れ", finished_at: Time.current) }
    expired = new_job(scheduled_at: 1.hour.ago).tap { |j| j.update_columns(status: PrintJob.statuses[:expired], finished_at: Time.current) }
    overdue = new_job(scheduled_at: 30.minutes.ago)
    future = new_job(scheduled_at: 1.hour.from_now)

    get admin_print_jobs_path
    assert_select "#print_job_filters a[href=?]", admin_print_jobs_path(filter: :failed), text: /失敗ジョブ（1）/
    assert_select "#print_job_filters a[href=?]", admin_print_jobs_path(filter: :expired), text: /期限切れ（1）/
    assert_select "#print_job_filters a[href=?]", admin_print_jobs_path(filter: :overdue), text: /未印刷（予定超過）（1）/

    get admin_print_jobs_path(filter: :failed)
    assert_select "#print_job_#{failed.id}"
    assert_select "#print_job_#{expired.id}", false
    assert_select "#print_job_#{overdue.id}", false
    assert_select "#print_job_#{ok.id}", false

    get admin_print_jobs_path(filter: :expired)
    assert_select "#print_job_#{expired.id}"
    assert_select "#print_job_#{failed.id}", false

    get admin_print_jobs_path(filter: :overdue)
    assert_select "#print_job_#{overdue.id}"
    assert_select "#print_job_#{future.id}", false
    assert_select "#print_job_#{failed.id}", false
  end

  test "the heartbeat-lost filter lists unfinished jobs on stations that have gone silent" do
    live_job = new_job(scheduled_at: 1.minute.ago)
    @station.seen!("0.1.0") # 通信があるので途絶していない
    silent, = PrintStation.register!(name: "教室B")
    silent.update_columns(last_seen_at: 20.minutes.ago)
    silent_job = PrintJob.create_with_pdf!(station: silent, title: "静かな教室", data: PDF_BYTES, scheduled_at: 1.minute.ago)

    get admin_print_jobs_path
    assert_select "#print_job_heartbeat_lost_#{silent_job.id}"
    assert_select "#print_job_heartbeat_lost_#{live_job.id}", false
    assert_select "#print_job_filters a[href=?]", admin_print_jobs_path(filter: :heartbeat_lost), text: /ハートビート途絶（1）/

    get admin_print_jobs_path(filter: :heartbeat_lost)
    assert_select "#print_job_#{silent_job.id}"
    assert_select "#print_job_#{live_job.id}", false
  end

  test "an unknown filter is ignored (shows everything)" do
    job = new_job(scheduled_at: 1.minute.ago)
    get admin_print_jobs_path(filter: "nonsense")
    assert_response :success
    assert_select "#print_job_#{job.id}"
    assert_select "#print_job_filters a", text: "すべて"
  end

  test "cancel needs a confirmation" do
    new_job(scheduled_at: 1.minute.ago)
    get admin_print_jobs_path
    assert_select "form[action$='/cancel'] [data-turbo-confirm]", minimum: 1
  end

  test "an uploaded pdf over 30MB is refused and creates no job" do
    big = "%PDF-1.4\n" + ("x" * 31.megabytes)
    file = Rack::Test::UploadedFile.new(StringIO.new(big), "application/pdf", original_filename: "big.pdf")
    assert_no_difference -> { PrintJob.count } do
      post admin_print_jobs_path, params: { print_job: { pdf: file, print_station_id: @station.id } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /大きすぎ/
  end

  test "a very long title (file name) is truncated to the limit" do
    file = Rack::Test::UploadedFile.new(StringIO.new(PDF_BYTES), "application/pdf", original_filename: "#{'a' * 200}.pdf")
    post admin_print_jobs_path, params: { print_job: { pdf: file, print_station_id: @station.id } }
    assert_redirected_to admin_print_jobs_path
    assert_equal PrintJob::TITLE_MAX, PrintJob.last.title.length
  end
end
