require "application_system_test_case"

class TwoFactorSetupTest < ApplicationSystemTestCase
  def log_in
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  def rect(selector)
    page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right }; })()").symbolize_keys
  end

  # SCREENSHOTS=1 で tmp/nav_shots/ に PR 用の画像を出す
  def shot(name)
    return unless ENV["SCREENSHOTS"]
    FileUtils.mkdir_p(Rails.root.join("tmp/nav_shots"))
    page.save_screenshot(Rails.root.join("tmp/nav_shots/#{name}.png").to_s)
  end

  [ [ 1400, 1400 ], [ 768, 1024 ] ].each do |width, height|
    test "the QR code stays inside its card and above the code field at #{width}px" do
      page.driver.browser.manage.window.resize_to(width, height)
      log_in
      visit new_two_factor_path
      assert_selector "#otp-qr svg"

      card = rect("#otp-qr")
      svg = rect("#otp-qr svg")
      secret = rect("#otp-secret")
      input = rect("input[name='code']")

      assert_operator card[:right] - card[:left], :<=, 220.5, "the card is at most 220px wide"
      assert_operator svg[:bottom], :<=, card[:bottom] + 0.5, "the QR is drawn inside the card"
      assert_operator svg[:right], :<=, card[:right] + 0.5, "the QR is drawn inside the card"
      assert_operator card[:bottom], :<=, secret[:top], "the manual key sits below the QR"
      assert_operator card[:bottom], :<, input[:top], "the QR does not overlap the code field"
      assert_operator secret[:right], :<=, width, "the manual key wraps instead of overflowing"
      shot("two_factor_setup_#{width}")
    end
  end
end
