require "test_helper"

class VersionControllerTest < ActionDispatch::IntegrationTest
  def with_env(value)
    old = ENV["RENDER_GIT_COMMIT"]
    value.nil? ? ENV.delete("RENDER_GIT_COMMIT") : ENV["RENDER_GIT_COMMIT"] = value
    yield
  ensure
    old.nil? ? ENV.delete("RENDER_GIT_COMMIT") : ENV["RENDER_GIT_COMMIT"] = old
  end

  test "returns RENDER_GIT_COMMIT without signing in, and nothing but sha and booted_at" do
    with_env("0123456789abcdef0123456789abcdef01234567") do
      get "/up/version"
    end
    assert_response :success
    body = response.parsed_body
    assert_equal "0123456789abcdef0123456789abcdef01234567", body["sha"]
    assert_equal %w[booted_at sha], body.keys.sort
    assert_nothing_raised { Time.iso8601(body["booted_at"]) }
  end

  test "returns unknown when RENDER_GIT_COMMIT is unset or blank" do
    [ nil, "" ].each do |v|
      with_env(v) { get "/up/version" }
      assert_response :success
      assert_equal "unknown", response.parsed_body["sha"]
    end
  end

  test "the standard /up check is unchanged" do
    get "/up"
    assert_response :success
  end
end
