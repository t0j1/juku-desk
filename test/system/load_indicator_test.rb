require "application_system_test_case"

# 遅いページ遷移の読み込み表示。fetch を遅らせて、サーバーが遅い状況を作る
class LoadIndicatorTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1440, 1000)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
  end

  def slow_fetch(ms)
    page.execute_script(<<~JS)
      if (!window.__origFetch) window.__origFetch = window.fetch
      window.fetch = (...args) => new Promise((resolve) => setTimeout(() => resolve(window.__origFetch(...args)), #{ms}))
    JS
  end

  # 100ms ごとに、表示の進み具合を記録する（sessionStorage へ。初回の資産の差し替えで全面再読み込みになっても残る）
  def watch_indicator
    page.execute_script(<<~JS)
      sessionStorage.setItem("liShown", "0"); sessionStorage.setItem("liProgress", "[]")
      window.__liTimer = setInterval(() => {
        const el = document.getElementById("load-indicator")
        if (!el) return
        if (!el.hidden) sessionStorage.setItem("liShown", "1")
        if (el.dataset.progress) sessionStorage.setItem("liProgress", JSON.stringify(JSON.parse(sessionStorage.getItem("liProgress")).concat(parseFloat(el.dataset.progress))))
      }, 100)
    JS
  end

  def thresholds(show: 400, reason: 3000, estimate: 15000, slow: 45000)
    page.execute_script(<<~JS)
      const el = document.getElementById("load-indicator")
      el.dataset.loadIndicatorShowMsValue = #{show}; el.dataset.loadIndicatorReasonMsValue = #{reason}
      el.dataset.loadIndicatorEstimateMsValue = #{estimate}; el.dataset.loadIndicatorSlowMsValue = #{slow}
    JS
  end

  test "a fast navigation shows nothing" do
    watch_indicator
    slow_fetch(100)
    thresholds(show: 1500) # 画面の既定は 0.4 秒。負荷の高い CI でも揺れないよう、応答の遅れ（0.1 秒）との差を大きく取る
    click_on "小テスト作成"
    assert_current_path new_quiz_path
    sleep 0.3
    assert_equal "0", page.evaluate_script("sessionStorage.getItem('liShown')")
    assert_no_selector "#load-indicator", visible: :visible
  end

  test "a slow navigation shows the indicator after 0.4s, the reason after 3s, never goes backwards or past 99%, and goes away when done" do
    watch_indicator
    slow_fetch(4500)
    click_on "小テスト作成"
    assert_selector "#load-indicator[data-state=loading]", text: "読み込み中", wait: 2
    assert_no_text "サーバーを起動しています", wait: 0
    assert_selector "#load-indicator[data-state=reason]", text: "サーバーを起動しています（無料枠のため最大 1 分ほどかかります）", wait: 4
    assert_selector "#load-indicator[aria-busy=true] [role=status]"
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"), "no horizontal scroll"
    assert_no_selector "#load-indicator", visible: :visible, wait: 8
    values = JSON.parse(page.evaluate_script("sessionStorage.getItem('liProgress')"))
    assert_operator values.size, :>, 3
    assert_equal values.sort, values, "progress never goes backwards"
    assert values.all? { |v| v <= 0.99 }, "progress never passes 99%"
  end

  test "after the estimate threshold the bar looks estimated, and after the slow threshold a reload button appears" do
    slow_fetch(5000)
    thresholds(show: 200, reason: 400, estimate: 800, slow: 1600)
    click_on "小テスト作成"
    assert_selector "#load-indicator[data-state=estimate]", text: "所要時間は推定できません", wait: 3
    assert_equal "block", find(".load-stripes", visible: :all).evaluate_script("getComputedStyle(this).display")
    assert_selector "#load-indicator[data-state=slow] button", text: "再読み込み", wait: 3
    assert_current_path new_quiz_path, wait: 8
  end

  test "with reduced motion the bar and stripes do not move" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit students_path
    watch_indicator
    slow_fetch(2500)
    thresholds(show: 200, estimate: 400)
    click_on "小テスト作成"
    assert_selector "#load-indicator[data-state=estimate]", wait: 3
    assert_no_selector ".load-bar", visible: :visible
    assert_equal "none", find(".load-stripes", visible: :all).evaluate_script("getComputedStyle(this).animationName")
    assert_empty JSON.parse(page.evaluate_script("sessionStorage.getItem('liProgress')"))
    assert_current_path new_quiz_path, wait: 5
  end
end
