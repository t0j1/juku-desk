require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "role defaults to instructor and ranks" do
    assert User.new.instructor?
    assert_not users(:instructor).manager_or_above?
    assert users(:manager).manager_or_above?
    assert users(:admin).manager_or_above?
  end

  test "requires name" do
    assert_not User.new(email_address: "x@example.com", password: "password").valid?
  end
end
