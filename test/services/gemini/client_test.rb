require "test_helper"
require "socket"

# 実際の HTTP で、リクエストの形（キーはヘッダー・response_schema など）と、応答の解釈を確かめる。ローカルの小さなサーバーを使い、本物の Gemini には繋がない。
class Gemini::ClientTest < ActiveSupport::TestCase
  setup do
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = []
    ENV["GEMINI_ENDPOINT"] = "http://127.0.0.1:#{@server.addr[1]}"
    ENV["GEMINI_API_KEY"] = "secret-key-#{SecureRandom.hex(6)}"
  end

  teardown do
    @server.close
    %w[GEMINI_ENDPOINT GEMINI_API_KEY GEMINI_MODEL GEMINI_TIMEOUT_SECONDS].each { |k| ENV.delete(k) }
  end

  # 1 回だけ受けて、status と body を返す
  def serve(status, body, delay: 0)
    @thread = Thread.new do
      socket = @server.accept
      head = +""
      while (line = socket.gets)
        head << line
        break if line == "\r\n"
      end
      length = head[/content-length: (\d+)/i, 1].to_i
      payload = socket.read(length)
      @requests << { head: head, body: payload }
      sleep delay
      socket.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    rescue IOError, Errno::EPIPE
      nil
    end
  end

  def generate = Gemini::Client.new.generate("\xFF\xD8\xFFimage".b, mime_type: "image/jpeg")

  test "sends the key in a header only, with response_mime_type and response_schema, and returns the JSON text" do
    ENV["GEMINI_MODEL"] = "gemini-test-model"
    serve 200, { candidates: [ { content: { parts: [ { text: gemini_json } ] } } ] }.to_json
    assert_equal JSON.parse(gemini_json), JSON.parse(generate)
    @thread.join

    request = @requests.first
    assert_match %r{\APOST /v1beta/models/gemini-test-model:generateContent HTTP/1.1}, request[:head]
    assert_no_match(/#{ENV['GEMINI_API_KEY']}/, request[:head].lines.first, "キーを URL に載せない")
    assert_match(/x-goog-api-key: #{ENV['GEMINI_API_KEY']}/i, request[:head])
    body = JSON.parse(request[:body])
    config = body["generationConfig"]
    assert_equal "application/json", config["response_mime_type"]
    assert_equal %w[answer_text confidence explanation options question_text subject tags], config["response_schema"]["properties"].keys.sort
    assert_equal Question::SUBJECTS, config["response_schema"]["properties"]["subject"]["enum"]
    part = body.dig("contents", 0, "parts", 1, "inline_data")
    assert_equal "image/jpeg", part["mime_type"]
    assert_equal "\xFF\xD8\xFFimage".b, Base64.strict_decode64(part["data"])
  end

  test "a per-minute 429 is retryable; a per-day RESOURCE_EXHAUSTED is the daily quota" do
    serve 429, { error: { status: "RESOURCE_EXHAUSTED", message: "rate", details: [ { violations: [ { quotaId: "GenerateRequestsPerMinutePerProjectPerModel" } ] } ] } }.to_json
    assert_raises(Gemini::Retryable) { generate }
    @thread.join

    serve 429, { error: { status: "RESOURCE_EXHAUSTED", message: "quota", details: [ { violations: [ { quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier" } ] } ] } }.to_json
    assert_raises(Gemini::DailyQuotaExceeded) { generate }
    @thread.join
  end

  test "5xx is retryable and a 400 is a plain error that never leaks the key" do
    serve 503, "{}"
    assert_raises(Gemini::Retryable) { generate }
    @thread.join

    serve 400, { error: { message: "bad request" } }.to_json
    error = assert_raises(Gemini::Error) { generate }
    assert_no_match(/#{ENV['GEMINI_API_KEY']}/, error.message)
    assert_not_kind_of Gemini::Retryable, error
    @thread.join
  end

  test "a timeout is retryable" do
    ENV["GEMINI_TIMEOUT_SECONDS"] = "1"
    serve 200, "{}", delay: 3
    assert_raises(Gemini::Retryable) { generate }
    @thread.kill
  end
end
