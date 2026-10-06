require "test_helper"

# 1日のスケジュールに、年間スケジュール（Supabase events）のその日の予定を読み取り専用で出す
class DailyScheduleAnnualTest < ActionDispatch::IntegrationTest
  DAY = Date.new(2026, 10, 7)

  setup do
    sign_in_as users(:staff)
    @env = ENV.to_h.slice("SUPABASE_URL", "SUPABASE_ANON_KEY")
    ENV["SUPABASE_URL"] = "https://example.supabase.co"
    ENV["SUPABASE_ANON_KEY"] = "anon-key"
    @calls = []
  end

  teardown do
    AnnualSchedule.transport = nil
    %w[ SUPABASE_URL SUPABASE_ANON_KEY ].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
  end

  def respond_with(status, rows)
    AnnualSchedule.transport = ->(date) { @calls << date; [ status, rows.to_json ] }
  end

  test "a lesson on the day appears as a read-only row with type, time and title" do
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "18:30:00", end_time: "21:40:00" } ]
    get daily_schedule_path(date: DAY.iso8601)
    assert_response :success
    assert_select "#annual-events .annual-event", count: 1, text: /18:30〜21:40.*高2授業.*数学/m
    assert_select "#annual-events a, #annual-events button, #annual-events form", count: 0
    assert_select ".btn-primary", count: 1, text: "タスクを追加"
  end

  test "a row without a time shows no time, and closures and holidays keep their own type colours" do
    respond_with 200, [ { type: "休講", title: "台風", start_time: nil, end_time: nil }, { type: "休暇", title: "", start_time: nil, end_time: nil } ]
    get daily_schedule_path(date: DAY.iso8601)
    assert_select ".annual-event", count: 2
    assert_select ".annual-event[style*=?]", AnnualSchedule::TYPE_COLORS["休講"]
    assert_select ".annual-event[style*=?]", AnnualSchedule::TYPE_COLORS["休暇"]
    assert_select "#annual-events", /時間なし/
  end

  test "an empty day shows nothing from the annual schedule" do
    respond_with 200, []
    get daily_schedule_path(date: DAY.iso8601)
    assert_response :success
    assert_select "#annual-events", count: 0
  end

  test "the real request asks only for published events of the day, with the anon key in headers and a 3 second timeout" do
    req = opts = nil
    http = Object.new
    http.define_singleton_method(:request) { |r| req = r; Struct.new(:code, :body).new("200", "[]") }
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |_host, _port, **o, &blk| opts = o; blk.call(http) }
    begin
      AnnualSchedule.new.events_on(DAY)
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
    query = URI.decode_www_form(URI(req.path.then { |p| "https://x#{p}" }).query).to_h
    assert_equal "eq.true", query["is_published"]
    assert_equal "eq.#{DAY.iso8601}", query["event_date"]
    assert_equal "anon-key", req["apikey"]
    assert_equal 3, opts[:read_timeout]
    assert_equal 3, opts[:open_timeout]
  end

  test "a failing or slow Supabase still opens the day with a notice instead of rows" do
    [ -> { [ 500, "error" ] }, -> { raise Net::ReadTimeout }, -> { [ 200, "not json" ] } ].each do |failure|
      AnnualSchedule.transport = ->(_date) { failure.call }
      get daily_schedule_path(date: DAY.iso8601)
      assert_response :success
      assert_select "#annual-events", /取得できません/
      assert_select ".btn-primary", text: "タスクを追加"
    end
  end

  test "results are cached for five minutes, failures are not" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: nil, end_time: nil } ]
    2.times { get daily_schedule_path(date: DAY.iso8601) }
    assert_equal 1, @calls.size
    AnnualSchedule.transport = ->(_d) { [ 500, "" ] }
    get daily_schedule_path(date: (DAY + 1).iso8601)
    get daily_schedule_path(date: (DAY + 1).iso8601)
    assert_select "#annual-events", /取得できません/
  ensure
    Rails.cache = original
  end

  test "without the environment variables nothing is requested and the screen is unchanged" do
    ENV.delete("SUPABASE_URL")
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: nil, end_time: nil } ]
    get daily_schedule_path(date: DAY.iso8601)
    assert_response :success
    assert_empty @calls
    assert_select "#annual-events", count: 0
  end
end
