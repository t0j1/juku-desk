# Gemini API の設定。キー・モデル・RPM/RPD・同時実行数・リトライはすべて環境変数から読む。
# API キーはここ以外で参照せず、ログにも出さない。
module GeminiConfig
  module_function

  def api_key = ENV["GEMINI_API_KEY"].presence
  def configured? = api_key.present?
  def model = ENV["GEMINI_MODEL"].presence || "gemini-2.5-flash"
  def endpoint = ENV["GEMINI_ENDPOINT"].presence || "https://generativelanguage.googleapis.com"
  def rpm = int("GEMINI_RPM", 10)
  def rpd = int("GEMINI_RPD", 250)
  def burst = int("GEMINI_BURST", 1)
  def max_concurrency = int("GEMINI_MAX_CONCURRENCY", 1)
  def timeout = int("GEMINI_TIMEOUT_SECONDS", 60)
  def max_retries = int("GEMINI_MAX_RETRIES", 5)
  def retry_base_seconds = Float(ENV["GEMINI_RETRY_BASE_SECONDS"].presence || 2)

  def int(name, default) = ENV[name].presence ? Integer(ENV[name]) : default
end
