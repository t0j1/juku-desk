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

  # 25 ページずつ (texts, 先頭ページ) を渡す TextExtractor.each_chunk の代わり。チャンクを渡す前に block（あれば）を実行
  def fake_extractor(&each_chunk)
    ->(_path, count, &blk) do
      (1..count).each_slice(25) do |c|
        each_chunk&.call(c.last)
        blk.call(Array.new(c.size, ""), c.first)
      end
    end
  end

  test "analysis percent rises monotonically up to 100 on a 255-page PDF" do
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    seen = []
    stub_class_method(PdfSplitter::TextExtractor, :each_chunk, fake_extractor { seen << JobProgress.find(progress.id).percent }) do
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
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    stub_class_method(PdfSplitter::TextExtractor, :each_chunk, fake_extractor { |done| progress.reload.request_cancel! if done == 100 }) do
      perform_enqueued_jobs
    end

    assert progress.reload.cancelled?
    assert_operator progress.done, :<, 255
    assert @job.reload.uploaded? # 「解析をやり直す」が出せる状態
    assert_nil @job.error_message
    assert_equal 0, @job.page_analyses.count # 途中までの結果は残さない
    assert @job.original_blob, "PDF 本体は残る"
  end

  test "analysis failure shows the reason" do
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    stub_class_method(PdfSplitter::TextExtractor, :each_chunk, ->(*) { raise PdfSplitter::Error, "ページ数が上限を超えています" }) do
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

  test "a split judged stale and then actually finished ends done, with progress and job in agreement" do
    make_outputs
    progress = enqueue(PdfSplitter::SplitJob, "pdf_split", 30)
    # ジョブ 1 件目の途中で 6 分止まり、その間に進捗の読み出しが stale と判定する（食い違いの再現）
    stalled = false
    store = ->(output, source_path:) do
      if !stalled
        stalled = true
        progress.reload.update_columns(updated_at: 6.minutes.ago)
        JobProgress.find(progress.id).fail_if_stale!
        assert @job.reload.failed?, "stale 判定でジョブも failed になる"
      end
    end
    stub_class_method(PdfSplitter::Builder, :ensure_stored, store) { perform_enqueued_jobs }

    progress.reload
    assert progress.succeeded?, "実際に完了したので、failed 表示のままにしない（#{progress.status}）"
    assert_equal 30, progress.done
    assert_nil progress.message.to_s[/止まりました/]
    assert @job.reload.done?
  end

  test "revive puts a wrongly failed job back to processing" do
    @job.update!(status: :analyzing)
    progress = enqueue(PdfSplitter::AnalyzeJob, "pdf_analyze", 255)
    progress.start!(total: 255) # ジョブ側のオブジェクト
    progress.update_columns(updated_at: 10.minutes.ago)
    JobProgress.find(progress.id).fail_if_stale! # 画面側の読み出しが stale と判定
    assert @job.reload.failed?

    progress.step!(100, "解析中 100/255ページ（39%）") # 動いていた
    assert @job.reload.analyzing?
    assert_nil @job.error_message
    assert JobProgress.find(progress.id).running?
  end
end
