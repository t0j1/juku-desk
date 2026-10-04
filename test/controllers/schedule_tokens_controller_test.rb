require "test_helper"

class ScheduleTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @old = ENV["SUPABASE_JWT_SECRET"]
    ENV["SUPABASE_JWT_SECRET"] = "dummy secret for tests"
  end

  teardown { @old.nil? ? ENV.delete("SUPABASE_JWT_SECRET") : ENV["SUPABASE_JWT_SECRET"] = @old }

  test "signed-in user gets a fresh token (no-store)" do
    sign_in_as users(:staff)
    post schedule_token_path
    assert_response :success
    body = response.parsed_body
    assert_equal 3, body["token"].split(".").size
    assert_in_delta 10.minutes.from_now.to_i, body["exp"], 5
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "viewer can refresh too (not a write)" do
    sign_in_as users(:viewer)
    post schedule_token_path
    assert_response :success
  end

  test "401 when not logged in" do
    post schedule_token_path
    assert_response :unauthorized
  end

  test "401 after logout" do
    sign_in_as users(:staff)
    delete session_path
    post schedule_token_path
    assert_response :unauthorized
  end

  test "401 after the session is revoked" do
    sign_in_as users(:staff)
    other = users(:staff).sessions.where.not(id: Current.session.id).first || users(:staff).sessions.create!
    Current.session.destroy!
    post schedule_token_path
    assert_response :unauthorized
    assert other
  end

  test "401 once the user is deactivated" do
    sign_in_as users(:staff)
    users(:staff).update!(active: false)
    post schedule_token_path
    assert_response :unauthorized
  end

  test "204 and no token when SUPABASE_JWT_SECRET is unset" do
    ENV.delete("SUPABASE_JWT_SECRET")
    sign_in_as users(:staff)
    post schedule_token_path
    assert_response :no_content
  end
end
