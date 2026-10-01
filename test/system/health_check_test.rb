require "application_system_test_case"

class HealthCheckSystemTest < ApplicationSystemTestCase
  test "health check page renders in a browser" do
    visit rails_health_check_path
    assert_selector "body[style*='green']"
  end
end
