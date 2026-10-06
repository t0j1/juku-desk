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
  Result = Struct.new(:events, :error, keyword_init: true) do
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
    ENV["SUPABASE_URL"].present? && ENV["SUPABASE_ANON_KEY"].present?
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

    events = fetch(date)
    Rails.cache.write(key, events, expires_in: CACHE_TTL) # 失敗はキャッシュしない
    Result.new(events: events, error: false)
  rescue StandardError => e
    Rails.logger.warn("[AnnualSchedule] #{e.class}: #{e.message}")
    Result.new(events: [], error: true)
  end

  private
    def fetch(date)
      status, body = @transport.call(date)
      raise "Supabase が #{status} を返しました" unless status == 200

      JSON.parse(body).map { |row| Event.new(type: row["type"].to_s, title: row["title"].to_s, start_time: row["start_time"], end_time: row["end_time"]) }
    end

    # anon キーはヘッダーでだけ送る（URL・ログには出さない）
    def http_get(date)
      uri = URI.join(ENV["SUPABASE_URL"].to_s.chomp("/") + "/", "rest/v1/events")
      uri.query = URI.encode_www_form(select: "type,title,start_time,end_time", is_published: "eq.true", event_date: "eq.#{date.iso8601}", order: "start_time.asc.nullsfirst")
      req = Net::HTTP::Get.new(uri, "apikey" => ENV["SUPABASE_ANON_KEY"], "Authorization" => "Bearer #{ENV["SUPABASE_ANON_KEY"]}", "Accept" => "application/json")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) { |http| http.request(req) }
      [ res.code.to_i, res.body.to_s ]
    end
end
