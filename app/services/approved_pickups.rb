require "net/http"
require "json"

# 送迎（承認済みの便）のその日の一覧を、読み取り専用で取ってくる。生徒名・予約ID・連絡先は受け取らない（関数が返さない）。
# Supabase の RPC `get_approved_pickups_for_date(p_date)` を anon キーで呼ぶ。返却列: approved_time, party_count, max_capacity, pickup_place。
# 関数が未適用（404）・取得失敗・環境変数なしのときは空配列（送迎行を出さないだけで、画面は止めない）。
class ApprovedPickups
  Pickup = Struct.new(:time, :party_count, :max_capacity, :place, keyword_init: true) do
    def starts_at(date) = Time.zone.parse("#{date.iso8601} #{time}")

    def time_label = time.to_s[0, 5]
  end

  CACHE_TTL = AnnualSchedule::CACHE_TTL
  TIMEOUT = AnnualSchedule::TIMEOUT

  # テストでは ApprovedPickups.transport = ->(date) { [status, body_string] } で HTTP を差し替える
  class_attribute :transport, instance_accessor: false

  def initialize(transport: self.class.transport)
    @transport = transport || method(:http_post)
  end

  def on(date)
    return [] unless AnnualSchedule.configured?

    key = "approved_pickups/#{date.iso8601}"
    cached = Rails.cache.read(key)
    return cached if cached

    pickups = fetch_with_reason(date)
    Rails.cache.write(key, pickups, expires_in: CACHE_TTL)
    pickups
  rescue StandardError => e
    Rails.logger.warn("[ApprovedPickups] #{e.class}: #{e.message}")
    []
  end

  private
    def fetch_with_reason(date)
      status, body = @transport.call(date)

      case status
      when 200
        JSON.parse(body).filter_map do |row|
          next if row["approved_time"].blank?
          Pickup.new(time: row["approved_time"], party_count: row["party_count"].to_i, max_capacity: row["max_capacity"].to_i, place: row["pickup_place"].to_s)
        end
      when 404
        log_with_host("HTTP 404")
        []
      when 401, 403
        log_with_host("HTTP #{status}")
        []
      when 0
        log_with_host("Timeout")
        []
      else
        log_with_host("HTTP #{status}")
        []
      end
    rescue Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout
      log_with_host("Timeout")
      []
    rescue JSON::ParserError
      log_with_host("Invalid JSON")
      []
    rescue StandardError => e
      log_with_host("Error: #{e.class}")
      []
    end

    def log_with_host(msg)
      url = AnnualSchedule.sanitized_url
      host = URI.parse(url).host rescue "unknown"
      Rails.logger.warn("[ApprovedPickups] #{msg} (host=#{host})")
    end

    def http_post(date)
      base_url = AnnualSchedule.sanitized_url
      key = AnnualSchedule.sanitized_key
      uri = URI.join(base_url + "/", "rest/v1/rpc/get_approved_pickups_for_date")
      req = Net::HTTP::Post.new(uri, "apikey" => key, "Authorization" => "Bearer #{key}", "Content-Type" => "application/json", "Accept" => "application/json")
      req.body = { p_date: date.iso8601 }.to_json
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) { |http| http.request(req) }
      [ res.code.to_i, res.body.to_s ]
    end
end
