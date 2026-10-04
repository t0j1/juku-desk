require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # ログイン後の「パスワードを保存」バブルが入力フォーカスを奪うのを防ぐ
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
  end

  # 一部のテストが resize_to で窓幅を変えるが、ブラウザはテスト間で使い回されるため、
  # 768px 未満が残るとサイドバーが畳まれて後続テストのリンクが見えなくなる。毎回既定の幅に戻す。
  setup do
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
