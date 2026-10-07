require "net/http"
require "json"

# 年間スケジュール（sekigaku-schedule の Supabase `events`）のその日の予定を、読み取り専用で取ってくる。
# 読むのは公開済み（is_published=true）の行だけ・anon キーだけ。書き戻しはしない。
# SUPABASE_URL / SUPABASE_ANON_KEY が未設定なら何もしない（configured? が false）。
class AnnualSchedule
  Event = Struct.new(:type, :title, :start_time, :end_time, keyword_init: true) do
    def time_label
      return nil if start_time.blank?
      [ start_time, end_time ].compact_blank.map { |t| t[0, 5] }.join("〜")
    end

    def timed? = start_time.present?

    def starts_at(date) = Time.zone.parse("#{date.iso8601} #{start_time}")

    def ends_at(date) = end_time.present? ? Time.zone.parse("#{date.iso8601} #{end_time}") : nil

    # 授業中（開始 ≦ いま < 終了）。終了時刻がなければ進行中とは言わない
    def ongoing?(date, now) = timed? && ends_at(date).present? && starts_at(date) <= now && now < ends_at(date)
  end

  # error が true のときは「取得できません」を出す（events は空）
  # error_reason で失敗理由の種別を持つ: :not_found, :timeout, :config_error, :unknown
  Result = Struct.new(:events, :error, :error_reason, keyword_init: true) do
    # 時刻つきはタスクと同じタイムラインに混ぜ、時刻なし（休暇・休講など）は上部のブロックに残す
    def timed = events.select(&:timed?)

    def untimed = events.reject(&:timed?)
  end

  CACHE_TTL = 5.minutes
  TIMEOUT = 3 # 秒
  # event_types の初期色（schema.sql）。知らない種別は DEFAULT_COLOR
  TYPE_COLORS = { "高1授業" => "#2a6fdb", "高2授業" => "#0e8a7d", "高3授業" => "#7a3fd1", "自習" => "#c27a00", "日曜自習室" => "#d1541f",
                  "講習" => "#c2306b", "休講" => "#b3273a", "休暇" => "#4f6b1e" }.freeze
  DEFAULT_COLOR = "#5b6472".freeze

  def self.configured?
    sanitized_url.present? && sanitized_key.present?
  end

  def self.sanitized_url
    raw = ENV["SUPABASE_URL"].to_s.strip
    # 末尾の / を除去
    raw = raw.chomp("/")
    # 末尾が /rest/v1 または /rest/v1/ なら除去（二重になって 404 になるため）
    raw = raw.sub(%r{/rest/v1/?$}, "")
    raw
  end

  def self.sanitized_key
    raw = ENV["SUPABASE_ANON_KEY"].to_s.strip
    # 前後の引用符を除去
    raw = raw.gsub(/\A["']|["']\z/, "")
    raw
  end

  def self.color_for(type) = TYPE_COLORS.fetch(type, DEFAULT_COLOR)

  # テストでは AnnualSchedule.transport = ->(date) { [status, body_string] } で HTTP を差し替える
  class_attribute :transport, instance_accessor: false

  def initialize(transport: self.class.transport)
    @transport = transport || method(:http_get)
  end

  def events_on(date)
    return Result.new(events: [], error: false) unless self.class.configured?

    key = "annual_schedule/#{date.iso8601}"
    cached = Rails.cache.read(key)
    return Result.new(events: cached, error: false) if cached

    events, error_reason = fetch_with_reason(date)
    if error_reason
      # 失敗はキャッシュしない
      Result.new(events: [], error: true, error_reason: error_reason)
    else
      Rails.cache.write(key, events, expires_in: CACHE_TTL)
      Result.new(events: events, error: false)
    end
  rescue StandardError => e
    Rails.logger.warn("[AnnualSchedule] #{e.class}: #{e.message}")
    Result.new(events: [], error: true, error_reason: :unknown)
  end

  private
    def fetch_with_reason(date)
      status, body = @transport.call(date)

      case status
      when 200
        events = JSON.parse(body).map { |row| Event.new(type: row["type"].to_s, title: row["title"].to_s, start_time: row["start_time"], end_time: row["end_time"]) }
        [ events, nil ]
      when 404
        log_with_host("HTTP 404")
        [ [], :not_found ]
      when 401, 403
        log_with_host("HTTP #{status}")
        [ [], :config_error ]
      when 0
        # Net::ReadTimeout などで status が 0 になることがある
        log_with_host("Timeout")
        [ [], :timeout ]
      else
        log_with_host("HTTP #{status}")
        [ [], :unknown ]
      end
    rescue Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout
      log_with_host("Timeout")
      [ [], :timeout ]
    rescue JSON::ParserError
      log_with_host("Invalid JSON")
      [ [], :config_error ]
    rescue StandardError => e
      log_with_host("Error: #{e.class}")
      [ [], :unknown ]
    end

    def log_with_host(msg)
      url = self.class.sanitized_url
      host = URI.parse(url).host rescue "unknown"
      Rails.logger.warn("[AnnualSchedule] #{msg} (host=#{host})")
    end

    # anon キーはヘッダーでだけ送る（URL・ログには出さない）
    def http_get(date)
      base_url = self.class.sanitized_url
      key = self.class.sanitized_key
      uri = URI.join(base_url + "/", "rest/v1/events")
      uri.query = URI.encode_www_form(select: "type,title,start_time,end_time", is_published: "eq.true", event_date: "eq.#{date.iso8601}", order: "start_time.asc.nullsfirst")
      req = Net::HTTP::Get.new(uri, "apikey" => key, "Authorization" => "Bearer #{key}", "Accept" => "application/json")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) { |http| http.request(req) }
      [ res.code.to_i, res.body.to_s ]
    end
end
