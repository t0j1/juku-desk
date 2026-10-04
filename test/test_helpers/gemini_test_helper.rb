# Gemini をモックする。実際の API は呼ばない。
module GeminiTestHelper
  VALID = { "subject" => "英語", "question_text" => "次の英文の（ ）に入る語を選べ。I (  ) a student.", "options" => [ "am", "is", "are" ],
            "answer_text" => "am", "explanation" => "主語が I のとき be 動詞は am。", "tags" => [ "be動詞", "中1" ], "confidence" => 0.92 }.freeze

  # 呼ばれるたびに responses の先頭を返す（String は本文、例外は raise、Proc は呼び出す）。足りなくなったら最後を繰り返す
  class FakeClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = 0
      @mutex = Mutex.new
    end

    def generate(_image, mime_type:, **)
      @mutex.synchronize { @calls += 1 }
      response = @responses.length > 1 ? @responses.shift : @responses.first
      response = response.call(@calls) if response.respond_to?(:call)
      raise response if response.is_a?(Exception)

      response
    end
  end

  def gemini_json(overrides = {})
    VALID.merge(overrides).to_json
  end

  def with_gemini(*responses, rpm: 600, rpd: 1000)
    ENV["GEMINI_API_KEY"] = "test-key-#{SecureRandom.hex(4)}"
    ENV["GEMINI_RPM"] = rpm.to_s
    ENV["GEMINI_RPD"] = rpd.to_s
    ENV["GEMINI_RETRY_BASE_SECONDS"] = "2"
    @sleeps = []
    Marking::Extractor.sleeper = ->(seconds) { @sleeps << seconds; travel(seconds.ceil.seconds) } # 待ち時間は、時計を進めて済ませる
    @gemini = FakeClient.new(*responses)
    Marking::Extractor.client = @gemini
  end

  def reset_gemini
    %w[GEMINI_API_KEY GEMINI_RPM GEMINI_RPD GEMINI_RETRY_BASE_SECONDS GEMINI_MAX_RETRIES].each { |k| ENV.delete(k) }
    Marking::Extractor.sleeper = nil
    Marking::Extractor.client = nil
  end

  def make_regions(count, status: :queued)
    upload = Upload.create!(sha256: SecureRandom.hex(32), r2_key: "marking/uploads/x.jpg", content_type: "image/jpeg", width: 800, height: 600, byte_size: 10)
    count.times.map do |i|
      key = "marking/crops/#{upload.sha256}/#{i}.jpg"
      ImageStorage.put_file(key, __FILE__, content_type: "image/jpeg") # 中身は使わない（Gemini はモック）
      upload.crop_regions.create!(bbox: { "x" => i, "y" => 0, "w" => 100, "h" => 50 }, r2_key: key, status: status)
    end
  end
end
