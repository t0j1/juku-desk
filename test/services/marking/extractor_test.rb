require "test_helper"

class Marking::ExtractorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
  end

  teardown do
    reset_gemini
    travel_back
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def run_all
    perform_enqueued_jobs(only: Marking::StructureJob)
  end

  test "extracts a question from a region and keeps the raw response" do
    with_gemini(gemini_json)
    region = make_regions(1).first
    Marking::Extractor.call(region)

    assert_equal "extracted", region.reload.status
    question = region.questions.sole
    assert_equal [ "英語", [ "am", "is", "are" ], "am", [ "be動詞", "中1" ] ], [ question.subject, question.options, question.answer_text, question.tags ]
    assert_equal 0.92, question.raw_ai.dig("response", "confidence")
    assert_nil question.reviewed_at
  end

  test "an invalid or null subject is saved as needs_review, not failed" do
    with_gemini(gemini_json("subject" => "音楽"), gemini_json("subject" => nil))
    a, b = make_regions(2)
    Marking::Extractor.call(a)
    Marking::Extractor.call(b)
    assert_equal %w[needs_review needs_review], [ a.reload.status, b.reload.status ]
    assert_nil a.questions.sole.subject
    assert_equal "音楽", a.questions.sole.raw_ai.dig("response", "subject") # 生の応答は残る
  end

  test "empty question_text or answer_text fails the region, and the raw response is kept" do
    with_gemini(gemini_json("answer_text" => " "), gemini_json("question_text" => ""))
    a, b = make_regions(2)
    Marking::Extractor.call(a)
    Marking::Extractor.call(b)
    assert_equal %w[failed failed], [ a.reload.status, b.reload.status ]
    assert_match(/answer_text/, a.error_message)
    assert a.questions.sole.raw_ai["response"].present?
    assert_equal 0, Question.reviewable.count
  end

  test "empty tags become 要確認; broken JSON fails" do
    with_gemini(gemini_json("tags" => []), "not json at all")
    a, b = make_regions(2)
    Marking::Extractor.call(a)
    Marking::Extractor.call(b)
    assert_equal [ "要確認" ], a.reload.questions.sole.tags
    assert_equal "failed", b.reload.status
  end

  test "a 429 followed by success is retried with exponential backoff and jitter" do
    with_gemini(Gemini::Retryable.new("429"), Gemini::Retryable.new("503"), gemini_json)
    region = make_regions(1).first
    Marking::Extractor.call(region)

    assert_equal "extracted", region.reload.status
    assert_equal 3, @gemini.calls
    assert_equal 2, @sleeps.size
    assert @sleeps[0].between?(2.0, 3.0), @sleeps.inspect   # 2^0 × base 2 に 0〜50% のジッター
    assert @sleeps[1].between?(4.0, 6.0), @sleeps.inspect   # 2^1 × base 2
  end

  test "gives up after 5 retries and fails only that region; the next one still runs" do
    with_gemini(*([ Gemini::Retryable.new("503") ] * 6), gemini_json)
    a, b = make_regions(2)
    Marking::Extractor.call(a)
    assert_equal "failed", a.reload.status
    assert_match(/5 回/, a.error_message)
    assert_equal 6, @gemini.calls
    assert_equal 5, @sleeps.size

    Marking::Extractor.call(b)
    assert_equal "extracted", b.reload.status
  end

  test "an unexpected error fails the region without raising, and the API key never appears in the message" do
    with_gemini(->(_) { raise "boom #{ENV['GEMINI_API_KEY']}" })
    region = make_regions(1).first
    assert_nothing_raised { Marking::Extractor.call(region) }
    assert_equal "failed", region.reload.status
    assert_no_match(/#{ENV['GEMINI_API_KEY']}/, region.error_message)
    assert_match(/FILTERED/, region.error_message)
  end

  test "15 regions are processed in order within the RPM (accepting is instant, work happens in jobs)" do
    with_gemini(gemini_json, rpm: 10)
    freeze_time # 時計は sleeper の travel でだけ進める
    regions = make_regions(15, status: :confirmed)
    assert_enqueued_jobs 1, only: Marking::StructureJob do # 15 件を 1 つのジョブ（進捗 1 件）で順に処理する
      assert_equal 15, Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id))).total
    end
    assert_equal [ "queued" ], regions.map { |r| r.reload.status }.uniq

    run_all
    assert_equal [ "extracted" ], regions.map { |r| r.reload.status }.uniq
    assert_equal 15, @gemini.calls
    # RPM 10 = 6 秒おき。最初の 1 件は待たず、あとの 14 件ぶんは 1 回ずつ待つ。
    # 実時間ではなく、スタブした sleeper に渡った待ち時間で確かめる（CI の速さに左右されない）
    assert_equal 14, @sleeps.size, @sleeps.inspect
    assert_equal [ 6.0 ] * 14, @sleeps.map { |s| s.round(3) }
    assert_equal 15, GeminiQuota.first.day_count
  end

  test "the Solid Queue concurrency limit comes from GEMINI_MAX_CONCURRENCY (default 1)" do
    assert_equal 1, Marking::StructureJob.concurrency_limit
    assert Marking::StructureJob.new(1).concurrency_key.end_with?("/gemini")
  end

  test "without GEMINI_API_KEY nothing is enqueued and regions stay confirmed" do
    regions = make_regions(2, status: :confirmed)
    assert_no_enqueued_jobs do
      assert_nil Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)))
    end
    assert_equal [ "confirmed" ], regions.map { |r| r.reload.status }.uniq
  end

  test "daily quota from Gemini: quota_exceeded (not failed), rest stay queued, audit log, banner data, auto-resume the next day" do
    daily = Gemini::DailyQuotaExceeded.new("daily")
    with_gemini(daily, gemini_json)
    regions = make_regions(4, status: :confirmed)
    Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)))

    freeze_time = Time.utc(2026, 10, 5, 20, 0, 0) # 太平洋時間 13:00
    travel_to freeze_time
    assert_difference -> { AuditLog.where(action: "gemini_daily_quota_exceeded").count }, 1 do
      run_all
    end

    statuses = regions.map { |r| r.reload.status }
    assert_equal %w[quota_exceeded queued queued queued], statuses
    assert_equal 1, @gemini.calls, "止まったあとは Gemini を呼ばない"
    assert_equal 0, Question.count

    log = AuditLog.find_by(action: "gemini_daily_quota_exceeded")
    assert_equal 4, log.metadata["remaining"]
    banner = Marking::Quota.banner
    assert_equal 4, banner[:remaining]
    assert_equal Time.utc(2026, 10, 6, 7, 0, 0), banner[:resume_at].utc
    assert_equal "Tokyo", banner[:resume_at].time_zone.name.split("/").last

    # 太平洋時間 0 時のあと（翌日）に自動で再開
    travel_to Time.utc(2026, 10, 6, 7, 2, 0)
    assert_enqueued_jobs 1, only: Marking::ResumeJob # 日次上限のとき、リセット後に再開するジョブが予約されている
    Marking::ResumeJob.perform_now
    assert_nil Marking::Quota.banner
    run_all
    assert_equal [ "extracted" ], regions.map { |r| r.reload.status }.uniq
    assert_equal 4, Question.count
  end

  test "ResumeJob is scheduled for just after the Pacific midnight reset" do
    with_gemini(Gemini::DailyQuotaExceeded.new("daily"))
    region = make_regions(1).first
    travel_to Time.utc(2026, 10, 5, 20, 0, 0)
    assert_enqueued_with(job: Marking::ResumeJob, at: Time.utc(2026, 10, 6, 7, 1, 0)) do
      Marking::Extractor.call(region)
    end
    assert_equal "quota_exceeded", region.reload.status
  end

  test "our own RPD counter also stops at the limit as quota_exceeded" do
    with_gemini(gemini_json, rpd: 2)
    regions = make_regions(4)
    regions.each { |r| Marking::Extractor.call(r) }
    assert_equal %w[extracted extracted quota_exceeded queued], regions.map { |r| r.reload.status }.then { |s| s.first(3) + [ "queued" ] }
    assert_equal 2, @gemini.calls
    assert_equal 1, AuditLog.where(action: "gemini_daily_quota_exceeded").count
  end

  test "processing the same region twice calls Gemini once" do
    with_gemini(gemini_json)
    region = make_regions(1).first
    2.times { Marking::Extractor.call(CropRegion.find(region.id)) }
    assert_equal 1, @gemini.calls
  end

  test "a region with two questions (〔1〕〔2〕) creates two questions; the label goes to source_label, not question_text" do
    with_gemini(gemini_questions_json({ "source_label" => "〔1〕", "question_text" => "be動詞を選べ。" }, { "source_label" => "〔2〕", "question_text" => "一般動詞を選べ。", "subject" => nil }))
    region = make_regions(1).first
    Marking::Extractor.call(region)

    assert_equal "needs_review", region.reload.status # 2 問目の科目が null なので要確認
    assert_equal [ [ "〔1〕", "be動詞を選べ。", "英語" ], [ "〔2〕", "一般動詞を選べ。", nil ] ], region.questions.map { |q| [ q.source_label, q.question_text, q.subject ] }
    assert_equal [ region.id ], Question.pluck(:region_id).uniq
  end

  test "a single question in the questions array still works, with a null source_label" do
    with_gemini(gemini_questions_json("source_label" => nil))
    region = make_regions(1).first
    Marking::Extractor.call(region)
    assert_equal "extracted", region.reload.status
    assert_equal 1, region.questions.count
    assert_nil region.questions.sole.source_label
  end

  test "re-extracting a region replaces its questions instead of piling them up" do
    with_gemini(gemini_questions_json({}, {}), gemini_json)
    region = make_regions(1).first
    Marking::Extractor.call(region)
    assert_equal 2, region.questions.count
    region.update!(status: :queued)
    Marking::Extractor.call(region)
    assert_equal 1, region.reload.questions.count
  end

  test "one broken question in the array fails the region and keeps the raw response" do
    with_gemini(gemini_questions_json({}, { "answer_text" => "" }))
    region = make_regions(1).first
    Marking::Extractor.call(region)
    assert_equal "failed", region.reload.status
    assert_match(/2 問目: answer_text が空です/, region.error_message)
    assert_equal 0, Question.reviewable.count
  end

  test "a 404 (model retired) is model_unavailable with its own message, not a plain failure, and can be re-queued" do
    with_gemini(Gemini::ModelUnavailable.new("Gemini のモデル gemini-2.5-flash が利用できません"), gemini_json)
    region = make_regions(1).first
    Marking::Extractor.call(region)

    assert_equal "model_unavailable", region.reload.status
    assert_equal "モデルが利用できません：GEMINI_MODELを更新してください", region.error_message
    assert_equal 1, @gemini.calls, "404 はやり直さない"
    assert_empty @sleeps
    assert_equal :model_unavailable, region.upload.extraction_status

    assert_equal 1, Marking::Enqueuer.call(region.upload.crop_regions.where(status: CropRegion::RETRYABLE_STATUSES)).total
    perform_enqueued_jobs(only: Marking::StructureJob)
    assert_equal "extracted", region.reload.status
  end
end
