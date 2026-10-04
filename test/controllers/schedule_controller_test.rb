require "test_helper"

class ScheduleControllerTest < ActionDispatch::IntegrationTest
  def with_schedule_web_url(value)
    old = ENV["SCHEDULE_WEB_URL"]
    value.nil? ? ENV.delete("SCHEDULE_WEB_URL") : ENV["SCHEDULE_WEB_URL"] = value
    yield
  ensure
    old.nil? ? ENV.delete("SCHEDULE_WEB_URL") : ENV["SCHEDULE_WEB_URL"] = old
  end

  test "requires login like the other screens" do
    %w[/schedule /schedule/admin /schedule/pickup].each do |path|
      get path
      assert_redirected_to new_session_path, path
    end
  end

  test "embeds SCHEDULE_WEB_URL plus the page path (trailing slash ignored)" do
    sign_in_as users(:staff)
    with_schedule_web_url("https://sekigaku.example.pages.dev/") do
      { "/schedule" => "/", "/schedule/admin" => "/admin", "/schedule/pickup" => "/pickup" }.each do |path, remote|
        get path
        assert_response :success
        assert_select "iframe#schedule-frame[src=?]", "https://sekigaku.example.pages.dev#{remote}"
      end
    end
  end

  test "shows the not-set message when SCHEDULE_WEB_URL is blank or not http(s)" do
    sign_in_as users(:staff)
    [ nil, "", "javascript:alert(1)", "not a url" ].each do |value|
      with_schedule_web_url(value) do
        get "/schedule"
        assert_response :success
        assert_select "iframe", false, value.inspect
        assert_select "#schedule-unset", /未設定/
      end
    end
  end

  test "without SUPABASE_JWT_SECRET the iframe has no token and no refresh controller (unchanged behaviour)" do
    sign_in_as users(:staff)
    with_schedule_web_url("https://sekigaku.example.pages.dev") do
      get "/schedule/admin"
      assert_select "iframe#schedule-frame[src=?]", "https://sekigaku.example.pages.dev/admin"
      assert_select "iframe[data-controller]", false
    end
  end

  test "with SUPABASE_JWT_SECRET the token goes in the URL fragment, never the query string, and the page is not cached" do
    sign_in_as users(:staff)
    with_schedule_web_url("https://sekigaku.example.pages.dev") do
      with_jwt_secret("dummy secret for tests") do
        get "/schedule/admin"
        src = css_select("iframe#schedule-frame").first["src"]
        uri = URI.parse(src)
        assert_nil uri.query
        assert_equal "/admin", uri.path
        assert_match(/\Atoken=[\w-]+\.[\w-]+\.[\w-]+\z/, uri.fragment)
        assert_select "iframe[data-controller=?][data-schedule-token-origin-value=?]", "schedule-token", "https://sekigaku.example.pages.dev"
        assert_includes response.headers["Cache-Control"], "no-store"
      end
    end
  end

  test "no token is issued when the schedule URL is unset" do
    sign_in_as users(:staff)
    with_schedule_web_url(nil) do
      with_jwt_secret("dummy secret for tests") do
        get "/schedule"
        assert_select "iframe", false
        assert_not_includes response.body, "token="
      end
    end
  end

  def with_jwt_secret(value)
    old = ENV["SUPABASE_JWT_SECRET"]
    ENV["SUPABASE_JWT_SECRET"] = value
    yield
  ensure
    old.nil? ? ENV.delete("SUPABASE_JWT_SECRET") : ENV["SUPABASE_JWT_SECRET"] = old
  end
end
