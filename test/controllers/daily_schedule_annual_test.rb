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
    ApprovedPickups.transport = ->(_date) { [ 200, "[]" ] }
  end

  teardown do
    AnnualSchedule.transport = nil
    ApprovedPickups.transport = nil
    %w[ SUPABASE_URL SUPABASE_ANON_KEY ].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
  end

  def respond_with(status, rows)
    AnnualSchedule.transport = ->(date) { @calls << date; [ status, rows.to_json ] }
  end

  test "a lesson on the day appears as a read-only row with type, time and title" do
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "18:30:00", end_time: "21:40:00" } ]
    get daily_schedule_path(date: DAY.iso8601)
    assert_response :success
    assert_select "#timeline .annual-timed", count: 1, text: /18:30〜21:40.*年間.*高2授業.*数学/m
    assert_select "#timeline .annual-timed a, #timeline .annual-timed button, #timeline .annual-timed form", count: 0
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

  test "an empty day shows the task and annual lines separately, with the published-only note and a text link" do
    respond_with 200, []
    get daily_schedule_path(date: DAY.iso8601)
    assert_select "#empty-tasks", text: "タスク: なし"
    assert_select "#empty-annual", text: "年間予定: この日は登録なし"
    assert_select "#timeline", /公開済みの予定だけ/
    assert_select "a#open-annual[href=?]", schedule_path
    assert_select ".btn-primary", count: 1, text: "タスクを追加"
  end

  test "the annual line is not shown when the annual schedule could not be read" do
    respond_with 500, []
    get daily_schedule_path(date: DAY.iso8601)
    assert_select "#empty-tasks"
    assert_select "#empty-annual", count: 0
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

  def make_task(name, time)
    DailyScheduleTask.create!(name: name, execution_time: time, repeat_type: "daily", execution_type: "create_draft", template_key: "daily_report", save_destination: "drafts", enabled: true)
  end

  def timeline_labels
    css_select("#timeline ol > li").map { |li| li["id"] == "now-line" ? "now" : (li["data-annual-at"] ? "annual:#{li["data-annual-at"]}" : "task") }
  end

  test "timed annual events are mixed into the timeline in time order, with a task at the same time shown too, and untimed ones stay on top" do
    make_task("朝の日報", "08:00")
    make_task("同時刻の日報", "19:20")
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "19:20:00", end_time: "22:00:00" }, { type: "休講", title: "台風", start_time: nil, end_time: nil } ]
    travel_to(Time.zone.local(2026, 10, 7, 23, 0)) { get daily_schedule_path(date: DAY.iso8601) }
    assert_equal [ "task", "task", "annual:19:20", "now" ], timeline_labels
    assert_select "#timeline ol > li:nth-child(2)", /同時刻の日報/
    assert_select "#annual-events .annual-event", count: 1, text: /時間なし.*休講/m
    assert_select "#timeline ol .annual-timed", /19:20〜22:00/
  end

  test "the now line sits at the right place among mixed rows and a lesson in progress is marked" do
    make_task("朝の日報", "08:00")
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "19:20:00", end_time: "22:00:00" } ]
    travel_to Time.zone.local(2026, 10, 7, 20, 0) do
      get daily_schedule_path(date: DAY.iso8601)
      assert_equal [ "task", "annual:19:20", "now" ], timeline_labels
      assert_select ".annual-timed .annual-ongoing", text: "進行中"
    end
    travel_to Time.zone.local(2026, 10, 7, 19, 0) do
      get daily_schedule_path(date: DAY.iso8601)
      assert_equal [ "task", "now", "annual:19:20" ], timeline_labels
      assert_select ".annual-ongoing", count: 0
    end
    travel_to Time.zone.local(2026, 10, 7, 22, 0) do
      get daily_schedule_path(date: DAY.iso8601)
      assert_select ".annual-ongoing", count: 0
    end
  end

  test "when the fetch fails the notice stays and the tasks still show" do
    make_task("朝の日報", "08:00")
    AnnualSchedule.transport = ->(_d) { [ 500, "" ] }
    get daily_schedule_path(date: DAY.iso8601)
    assert_select "#annual-events", /取得できません/
    assert_select "#task_#{DailyScheduleTask.last.id}"
    assert_select ".annual-timed", count: 0
  end

  test "no text on the annual rows is smaller than 16px" do
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "19:20:00", end_time: nil }, { type: "休暇", title: "", start_time: nil, end_time: nil } ]
    get daily_schedule_path(date: DAY.iso8601)
    assert_select "#annual-events .text-sm, #annual-events .text-xs, .annual-timed .text-sm, .annual-timed .text-xs", count: 0
  end

  def pickup_rows(*rows) = ApprovedPickups.transport = ->(_date) { [ 200, rows.to_json ] }

  test "approved pickups are mixed into the timeline by time, shown as 送迎 HH:MM／乗車 n/定員 without any name" do
    make_task("朝の日報", "08:00")
    respond_with 200, [ { type: "高2授業", title: "数学", start_time: "19:20:00", end_time: "22:00:00" } ]
    pickup_rows({ approved_time: "21:40:00", party_count: 3, max_capacity: 8, pickup_place: "駅前ロータリー", student_name: "山田" })
    travel_to(Time.zone.local(2026, 10, 7, 23, 0)) { get daily_schedule_path(date: DAY.iso8601) }
    assert_select "#timeline .pickup-row", count: 1, text: /送迎 21:40／乗車 3\/8.*駅前ロータリー/m
    assert_select ".pickup-row", text: /山田/, count: 0
    labels = css_select("#timeline ol > li").map { |li| li["data-pickup-at"] ? "pickup" : (li["data-annual-at"] ? "annual" : (li["id"] == "now-line" ? "now" : "task")) }
    assert_equal %w[ task annual pickup now ], labels
    assert_select ".pickup-row .text-sm, .pickup-row .text-xs", count: 0
  end

  test "a pickup at the same time as a task shows both" do
    make_task("同時刻の日報", "21:40")
    pickup_rows({ approved_time: "21:40:00", party_count: 1, max_capacity: 4, pickup_place: "" })
    get daily_schedule_path(date: DAY.iso8601)
    assert_select "#timeline ol .pickup-row", count: 1
    assert_select "#timeline ol", text: /同時刻の日報/
  end

  test "an unapplied function (404), an error or bad json hides only the pickup rows and the screen stays 200" do
    make_task("朝の日報", "08:00")
    respond_with 200, []
    [ -> { [ 404, "{}" ] }, -> { [ 500, "" ] }, -> { raise Net::ReadTimeout }, -> { [ 200, "oops" ] } ].each do |failure|
      ApprovedPickups.transport = ->(_d) { failure.call }
      get daily_schedule_path(date: DAY.iso8601)
      assert_response :success
      assert_select ".pickup-row", count: 0
      assert_select "#timeline", text: /朝の日報/
      assert_select "#annual-events", count: 0
    end
  end

  test "the pickup request is an rpc POST with the date, anon key in headers, and 3 second timeouts" do
    req = opts = nil
    http = Object.new
    http.define_singleton_method(:request) { |r| req = r; Struct.new(:code, :body).new("200", "[]") }
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |_host, _port, **o, &blk| opts = o; blk.call(http) }
    begin
      ApprovedPickups.transport = nil
      ApprovedPickups.new.on(DAY)
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
    assert_equal "POST", req.method
    assert_equal "/rest/v1/rpc/get_approved_pickups_for_date", req.path
    assert_equal({ "p_date" => DAY.iso8601 }, JSON.parse(req.body))
    assert_equal "anon-key", req["apikey"]
    assert_equal 3, opts[:read_timeout]
  end

  test "without the environment variables no pickup is requested" do
    ENV.delete("SUPABASE_URL")
    called = false
    ApprovedPickups.transport = ->(_d) { called = true; [ 200, "[]" ] }
    get daily_schedule_path(date: DAY.iso8601)
    assert_response :success
    assert_not called
  end
end
