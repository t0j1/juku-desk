require "test_helper"

# 解析・分割の進捗とキャンセル。PDF を実際には読まず（qpdf / pdftotext なしで動く）、進み方と後始末だけを確かめる
class PdfSplitter::ProgressTest < ActiveJob::TestCase
  setup do
    JobProgress.save_interval = 0.seconds
    @user = users(:staff)
    @job = @user.pdf_split_jobs.create!(original_filename: "big.pdf", page_count: 255)
    @job.pdf_blobs.create!(kind: "original", data: "%PDF-dummy", byte_size: 10, expires_at: 7.days.from_now)
  end

  teardown { JobProgress.save_interval = 2.seconds }

  # Minitest 6 には stub が無いので、クラスのメソッドを差し替えて元に戻す
  def stub_class_method(klass, name, callable)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*args, **kw, &blk| callable.call(*args, **kw, &blk) }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def enqueue(klass, kind, total)
    JobProgress.enqueue(klass, user: @user, kind: kind, title: kind, subject: @job, total: total)
  end

  # 25 ページずつ「済んだ」と知らせる TextExtractor の代わり。呼ぶたびに block（あれば）を実行
  def fake_extractor(&each_chunk)
    ->(_path, count, &on_pages) do
      (25..count).step(25).to_a.push(count).uniq.each { |done| each_chunk&.call(done); on_pages.call(done) }
      Array.new(count, "")
    end
  end

  test "analysis percent rises monotonically up to 100 on a 255-page PDF" do
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    seen = []
    stub_class_method(PdfSplitter::TextExtractor, :pages_from_path, fake_extractor { seen << JobProgress.find(progress.id).percent }) do
      perform_enqueued_jobs
    end

    assert_equal seen.sort, seen
    assert_equal seen.uniq, seen
    assert_operator seen.size, :>=, 5
    assert_equal 255, progress.reload.done
    assert progress.succeeded?
    assert_equal 100, progress.percent
    assert_equal "解析中 255/255ページ（100%）", progress.message
    assert @job.reload.analyzed?
  end

  test "cancelling an analysis stops it, leaves no partial result and keeps the original" do
    @job.page_analyses.create!(page: 1, raw_text: "古い結果")
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    stub_class_method(PdfSplitter::TextExtractor, :pages_from_path, fake_extractor { |done| progress.reload.request_cancel! if done == 100 }) do
      perform_enqueued_jobs
    end

    assert progress.reload.cancelled?
    assert_operator progress.done, :<, 255
    assert @job.reload.uploaded? # 「解析をやり直す」が出せる状態
    assert_nil @job.error_message
    assert_equal [ "古い結果" ], @job.page_analyses.pluck(:raw_text) # 今回の途中結果は書かれていない
    assert @job.original_blob, "PDF 本体は残る"
  end

  test "analysis failure shows the reason" do
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    stub_class_method(PdfSplitter::TextExtractor, :pages_from_path, ->(*) { raise PdfSplitter::Error, "ページ数が上限を超えています" }) do
      perform_enqueued_jobs
    end
    assert progress.reload.failed?
    assert_equal "ページ数が上限を超えています", progress.message
    assert @job.reload.failed?
  end

  def make_outputs
    @job.update!(status: :splitting, output_count: 3)
    3.times { |i| @job.outputs.create!(display_name: "o#{i}", page_from: i * 10 + 1, page_to: (i + 1) * 10, position: i) }
  end

  test "cancelling a split removes the outputs that were already built" do
    make_outputs
    progress = enqueue(PdfSplitter::SplitJob, "pdf_split", 30)
    built = 0
    store = ->(output, source_path:) do
      @job.pdf_blobs.create!(kind: "output", pdf_split_output: output, data: "x", byte_size: 1, expires_at: 7.days.from_now)
      built += 1
      progress.reload.request_cancel! if built == 2
    end
    stub_class_method(PdfSplitter::Builder, :ensure_stored, store) { perform_enqueued_jobs }

    assert progress.reload.cancelled?
    assert_equal 0, @job.outputs.count
    assert_equal 0, @job.pdf_blobs.where(kind: "output").count
    assert @job.original_blob
    assert @job.reload.analyzed?
    assert_equal 0, @job.output_count
  end

  test "cancelling a queued split cleans up without the job ever running" do
    make_outputs
    progress = enqueue(PdfSplitter::SplitJob, "pdf_split", 30)
    progress.request_cancel!

    assert progress.reload.cancelled?
    assert_equal 0, enqueued_jobs.size
    assert_equal 0, @job.outputs.count
    assert @job.reload.analyzed?
  end

  test "cancelling a queued analysis leaves the job re-analyzable" do
    @job.update!(status: :uploaded)
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    progress.request_cancel!
    assert progress.reload.cancelled?
    assert @job.reload.uploaded?
    assert_nil @job.active_progress
  end

  test "a successful split reports pages and finishes the job" do
    make_outputs
    progress = enqueue(PdfSplitter::SplitJob, "pdf_split", 30)
    stub_class_method(PdfSplitter::Builder, :ensure_stored, ->(*, **) { nil }) { perform_enqueued_jobs }
    assert progress.reload.succeeded?
    assert_equal 30, progress.done
    assert_match "分割中 3/3ファイル", progress.message
    assert @job.reload.done?
  end

  test "a stalled running progress also fails the job so the user can retry" do
    @job.update!(status: :analyzing)
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    progress.update_columns(status: JobProgress.statuses[:running], started_at: 20.minutes.ago, updated_at: 10.minutes.ago)
    progress.fail_if_stale!

    assert progress.reload.failed?
    assert @job.reload.failed?
    assert_match "止まりました", @job.error_message
  end

  test "an analysis whose job was deleted ends the progress instead of staying queued" do
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    @job.delete
    perform_enqueued_jobs
    assert progress.reload.finished?
  end
end
