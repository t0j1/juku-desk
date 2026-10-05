require "net/http"
require "json"
require "base64"

module Gemini
  # Gemini API（generateContent）を HTTP で直接呼ぶ薄いクライアント。
  # API キーはヘッダー（x-goog-api-key）でだけ送り、URL・ログ・例外メッセージには出さない。
  class Client
    # transport: ->(request_hash) { [status, body_string] } を渡すとテストで HTTP を差し替えられる
    def initialize(transport: nil)
      @transport = transport || method(:http_post)
    end

    # 画像（バイト列）を渡し、構造化された JSON の本文（String）を返す
    def generate(image_bytes, mime_type:, prompt: Gemini::Prompt::TEXT)
      status, body = @transport.call(path: "/v1beta/models/#{GeminiConfig.model}:generateContent", body: request_body(image_bytes, mime_type, prompt))
      case status
      when 200 then extract_text(body)
      when 429 then raise daily_quota?(body) ? DailyQuotaExceeded.new("Gemini の 1 日の上限に達しました") : Retryable.new("Gemini が 429（分あたりの上限）を返しました")
      when 500..599 then raise Retryable, "Gemini が #{status} を返しました"
      else raise Error, "Gemini が #{status} を返しました（#{error_message(body)}）"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => e
      raise Retryable, "Gemini への接続に失敗しました（#{e.class}）"
    end

    # このキーで generateContent を呼べるモデル名の一覧（"gemini-…" の形）。モデル名を決める・確認するときに使う
    def list_models
      status, body = @transport.call(method: :get, path: "/v1beta/models?pageSize=200", body: nil)
      raise Error, "Gemini が #{status} を返しました（#{error_message(body)}）" unless status == 200

      JSON.parse(body).fetch("models", []).select { |m| Array(m["supportedGenerationMethods"]).include?("generateContent") }.map { |m| m["name"].to_s.delete_prefix("models/") }.sort
    rescue JSON::ParserError
      raise Error, "Gemini の応答を読めませんでした"
    end

    private
      def request_body(image_bytes, mime_type, prompt)
        {
          contents: [ { parts: [ { text: prompt }, { inline_data: { mime_type: mime_type, data: Base64.strict_encode64(image_bytes) } } ] } ],
          generationConfig: {
            response_mime_type: "application/json",
            response_schema: Gemini::Schema::QUESTION,
            temperature: 0
          }
        }
      end

      def extract_text(body)
        parsed = JSON.parse(body)
        parsed.dig("candidates", 0, "content", "parts", 0, "text") or raise Error, "Gemini の応答に本文がありません"
      rescue JSON::ParserError
        raise Error, "Gemini の応答を読めませんでした"
      end

      # RESOURCE_EXHAUSTED のうち、quotaId に PerDay（日次）を含むものを日次上限とみなす
      def daily_quota?(body)
        error = JSON.parse(body)["error"] || {}
        return false unless error["status"] == "RESOURCE_EXHAUSTED"

        Array(error["details"]).any? do |d|
          Array(d["violations"]).any? { |v| "#{v['quotaId']} #{v['quotaMetric']}".match?(/PerDay/i) }
        end
      rescue JSON::ParserError
        false
      end

      def error_message(body)
        JSON.parse(body).dig("error", "message").to_s.truncate(200)
      rescue JSON::ParserError
        ""
      end

      def http_post(path:, body:, method: :post)
        uri = URI.join(GeminiConfig.endpoint, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = GeminiConfig.timeout
        headers = { "Content-Type" => "application/json", "x-goog-api-key" => GeminiConfig.api_key.to_s }
        request = method == :get ? Net::HTTP::Get.new(uri, headers) : Net::HTTP::Post.new(uri, headers)
        request.body = JSON.generate(body) if body
        response = http.request(request)
        [ response.code.to_i, response.body.to_s ]
      end
  end
end
