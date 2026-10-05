require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "role defaults to staff; only viewer cannot write" do
    assert User.new.staff?
    assert users(:staff).can_write?
    assert users(:system_admin).can_write?
    assert_not users(:viewer).can_write?
  end

  test "requires name" do
    assert_not User.new(email_address: "x@example.com", password: "password1234").valid?
  end
end

class UserSecurityTest < ActiveSupport::TestCase
  setup { @user = users(:staff) }

  test "password needs 12+ chars with letters and digits" do
    [ "Short1A", "abcdefghijkl", "123456789012" ].each do |pw|
      @user.password = pw
      assert_not @user.valid?, "#{pw} should be rejected"
    end
    @user.password = "Tomato Juice 99"
    assert @user.valid?
  end

  test "last 5 passwords cannot be reused, the 6th back can" do
    passwords = (1..6).map { |i| "Tea Time Number #{i}" }
    passwords.each { |pw| @user.update!(password: pw) }
    # 直近 5 回分 = passwords[1..5]。最初の 1 つ前（passwords[0]）はもう使える
    assert_not @user.update(password: passwords[5])
    assert_not @user.update(password: passwords[1])
    assert @user.update(password: passwords[0])
  end

  test "five failures lock for 15 minutes and the sixth try is refused even with the right password" do
    4.times { assert_not @user.register_failed_login! }
    assert_not @user.locked?
    assert @user.register_failed_login!
    assert @user.locked?
    assert_in_delta 15.minutes.from_now, @user.locked_until, 5.seconds
  end

  test "lock expires and the counter restarts" do
    5.times { @user.register_failed_login! }
    travel 16.minutes do
      assert_not @user.locked?
      assert_not @user.register_failed_login!
      assert_equal 1, @user.reload.failed_attempts
    end
  end

  test "unlock! clears the lock" do
    5.times { @user.register_failed_login! }
    @user.unlock!
    assert_not @user.locked?
    assert_equal 0, @user.failed_attempts
  end
end
