module Marking
  # confirmed になった領域 1 件を Gemini で構造化して questions に保存する。
  #
  # - 画像は R2 から 1 枚ずつ取り出して送る（同時実行は ExtractJob 側で GEMINI_MAX_CONCURRENCY=1）
  # - RPM はトークンバケット（GeminiQuota.acquire）で守る。429（分あたり）・5xx・タイムアウトは、指数バックオフ + ジッターで最大 GEMINI_MAX_RETRIES 回までやり直す
  # - 日次上限（自前の RPD カウンタ、または Gemini の RESOURCE_EXHAUSTED/PerDay）は failed にせず quota_exceeded。残りは queued のまま保留し、
  #   太平洋時間の 0 時のあとに自動で再開する
  # - モデルの廃止（404）は failed と分けて model_unavailable（GEMINI_MODEL を更新してから「構造化を開始・やり直す」）
  # - 1 つの領域から複数の問題（〔1〕〔2〕…）を作る。やり直したときは、その領域の問題を作り直す
  # - 1 件が失敗しても例外は外に出さない（ほかの領域の処理は止めない）
  class Extractor
    class << self
      # テストで待ち時間を差し替える
      attr_writer :sleeper, :client

      def sleeper = @sleeper || ->(seconds) { sleep(seconds) }
      def client = @client || Gemini::Client.new
    end

    def self.call(region) = new(region).call

    def initialize(region)
      @region = region
    end

    def call
      return unless claim

      image = ImageStorage.read(@region.r2_key)
      raw = request_with_retries(image)
      return unless raw # 日次上限で止まった

      save(Validator.call(raw, generate_answers: @region.generate_answers), raw)
    rescue Gemini::ModelUnavailable
      @region.update!(status: :model_unavailable, error_message: CropRegion::MODEL_UNAVAILABLE_MESSAGE)
    rescue StandardError => e
      fail_region(safe_message(e))
    end

    private
      # queued のものだけ処理中にする（二重実行・再投入でも 1 回だけ処理する）。日次上限で止まっている間は触らず queued のまま
      def claim
        return false if GeminiQuota.exceeded?

        @region.with_lock do
          return false unless @region.queued?

          @region.update!(status: :processing, error_message: nil)
        end
        true
      end

      def request_with_retries(image)
        attempts = 0
        begin
          wait_for_slot
          self.class.client.generate(image, mime_type: "image/jpeg", prompt: Gemini::Prompt.for(generate_answers: @region.generate_answers))
        rescue GeminiQuota::DailyLimit, Gemini::DailyQuotaExceeded
          hold_for_daily_quota
          nil
        rescue Gemini::Retryable => e
          attempts += 1
          raise Gemini::Error, "#{e.message}（#{GeminiConfig.max_retries} 回やり直しても成功しませんでした）" if attempts > GeminiConfig.max_retries

          self.class.sleeper.call(backoff(attempts))
          retry
        end
      end

      def wait_for_slot
        loop do
          wait = GeminiQuota.acquire
          break if wait <= 0

          self.class.sleeper.call(wait)
        end
      end

      # 2^n 秒 × base に、0〜50% のジッターを足す
      def backoff(attempt)
        base = GeminiConfig.retry_base_seconds * (2**(attempt - 1))
        base + rand * base * 0.5
      end

      def save(result, raw)
        if result.status == :failed
          @region.update!(status: :failed, error_message: result.error)
          return store_raw_only(raw, result)
        end

        @region.transaction do
          replace_questions(result.attributes.map { |attrs| attrs.merge(region_id: @region.id) })
          @region.update!(status: result.status, error_message: nil, extracted_at: Time.current)
        end
      end

      # スキーマ違反でも、生のレスポンスは残す（原因調査用）
      def store_raw_only(raw, result)
        response = result.raw.is_a?(Hash) ? result.raw : { "text" => raw.to_s.truncate(5000) }
        replace_questions([ { region_id: @region.id, raw_ai: { "response" => response, "model" => GeminiConfig.model, "error" => result.error } } ])
      end

      # やり直しのときは前回の問題を消して作り直す。テストに使われている問題（test_items が参照）は消せないので残す
      def replace_questions(rows)
        @region.questions.where.not(id: ExamItem.select(:question_id)).delete_all
        rows.each { |row| Question.create!(row) }
        @region.questions.reset
      end

      def hold_for_daily_quota
        @region.update!(status: :quota_exceeded, error_message: nil)
        Marking::Quota.trip!
      end

      def fail_region(message)
        @region.update!(status: :failed, error_message: message.truncate(500))
      end

      # 例外メッセージに API キーが紛れ込まないようにする
      def safe_message(error)
        message = "#{error.class}: #{error.message}"
        key = GeminiConfig.api_key
        key.present? ? message.gsub(key, "[FILTERED]") : message
      end
  end
end
