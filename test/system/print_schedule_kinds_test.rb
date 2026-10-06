require "application_system_test_case"

# 定例印刷の雛形 v2 の受入基準 9・10・13・14（docs/auto-print-roster-wordtest.md §10）
class PrintScheduleKindsSystemTest < ApplicationSystemTestCase
  setup do
    @station, = PrintStation.register!(name: "教室A")
    Wordbook.create!(name: "テスト帳").tap { |b| 3.times { |i| b.words.create!(number: i + 1, term: "w#{i}", meaning: "①m#{i}") } }
  end

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: users(:system_admin).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    fill_in "認証コード または リカバリーコード", with: current_totp
    click_on "ログイン"
    assert_no_selector "h1", text: "2段階認証"
  end

  def horizontal_overflow?
    page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end

  def visible_sections
    page.evaluate_script("Array.from(document.querySelectorAll('[data-exec-type-target=section]')).filter(e => !e.hidden && e.offsetParent !== null).map(e => e.dataset.type)").uniq
  end

  test "choosing a kind shows only that kind's data source fields (criterion 9, 14)" do
    log_in_as_admin
    visit new_admin_print_schedule_path
    assert_selector "[role=radiogroup] input[name='print_schedule[kind]']", visible: :all, count: 3

    find("label", text: "日次出席名簿").click
    assert_equal [ "roster" ], visible_sections
    assert_selector "span", text: "✓ 選択中", count: 1

    find("label", text: "単語テスト").click
    assert_equal [ "word_test" ], visible_sections
    assert_selector "span", text: "✓ 選択中", count: 1
  end

  test "the new form has no horizontal scroll at 1440px and stacks the kind cards below 1200px (criterion 13)" do
    log_in_as_admin
    page.driver.browser.manage.window.resize_to(1440, 1000)
    visit new_admin_print_schedule_path
    assert_selector "[role=radiogroup]"
    refute horizontal_overflow?
    wide = page.evaluate_script("Array.from(document.querySelectorAll('[role=radiogroup] > label')).map(e => Math.round(e.getBoundingClientRect().top))").uniq
    assert_equal 1, wide.size, "1440px では 3 枚が横並び"

    page.driver.browser.manage.window.resize_to(1100, 1000)
    visit new_admin_print_schedule_path
    assert_selector "[role=radiogroup]"
    refute horizontal_overflow?
    narrow = page.evaluate_script("Array.from(document.querySelectorAll('[role=radiogroup] > label')).map(e => Math.round(e.getBoundingClientRect().top))").uniq
    assert_equal 3, narrow.size, "1200px 未満では縦積み"
  end

  test "no visible text on the form is smaller than 16px (criterion 13)" do
    log_in_as_admin
    visit new_admin_print_schedule_path
    assert_selector "[role=radiogroup]"
    small = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('main *, form *')).filter(e => {
        if (e.offsetParent === null || !e.childNodes.length) return false
        const own = Array.from(e.childNodes).some(n => n.nodeType === 3 && n.textContent.trim() !== '')
        return own && parseFloat(getComputedStyle(e).fontSize) < 16
      }).map(e => e.tagName + ':' + e.textContent.trim().slice(0, 20))
    JS
    assert_empty small
  end

  test "a changed layout is saved and reflected in the summary on the edit screen (criterion 10)" do
    log_in_as_admin
    schedule = PrintSchedule.create!(name: "名簿", kind: "roster", print_station: @station, weekdays: [ 1 ], time_of_day: "08:00", copies: 1,
                                     source_config: { "target" => "all" })
    visit edit_admin_print_schedule_path(schedule)
    assert_selector "#layout_roster summary", text: "A4 縦・余白15mm・本文11pt"
    find("#layout_roster summary").click
    fill_in "layout_roster_body_size", with: "14"
    click_on "更新する"
    assert_text "を更新しました"
    visit edit_admin_print_schedule_path(schedule)
    assert_selector "#layout_roster summary", text: "本文14pt"
    assert_equal 14, schedule.reload.layout_config["body_size"].to_i
  end
end
