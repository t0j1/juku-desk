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
end
