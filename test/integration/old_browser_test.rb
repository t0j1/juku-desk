require "test_helper"

class OldBrowserTest < ActionDispatch::IntegrationTest
  test "older iPad Safari is not blocked" do
    get new_session_path, headers: { "User-Agent" => "Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1" }
    assert_response :success
  end
end
