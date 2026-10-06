# 印刷ステーションの削除確認モーダル（名前を打たないと削除できない）。仕様＝§6-4-9
class PrintStationDeleteTest < ApplicationSystemTestCase
  NAME = "碩学館1F大部屋 A-bizhub551i".freeze

  setup do
    @station, = PrintStation.register!(name: NAME)
    @other, = PrintStation.register!(name: "別の部屋")
  end

  def log_in_as_admin
    visit new_session_path
    fill_in "メールアドレス", with: users(:system_admin).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    fill_in "認証コード または リカバリーコード", with: current_totp
    click_on "ログイン"
    assert_no_selector "h1", text: "2段階認証"
    visit admin_print_stations_path
    assert_selector "#print_station_#{@station.id}"
  end

  def dialog_id = "delete_dialog_#{@station.id}"
  def input_id = "delete_name_#{@station.id}"
  def open_dialog
    within("#print_station_#{@station.id}") { click_on "削除" }
    assert_selector "##{dialog_id}[open]"
  end
  def submit_button = find("##{dialog_id} button[type=submit]", visible: :all)
  def active_id = page.evaluate_script("document.activeElement.id")

  test "削除を押すとアプリ内モーダルが開き、入力欄にフォーカスがあり、a11y属性がそろう" do
    log_in_as_admin
    open_dialog
    assert_equal input_id, active_id
    assert_equal "dialog", find("##{dialog_id}")[:role]
    assert_equal "true", find("##{dialog_id}")[:"aria-modal"]
    title = find("##{dialog_id}")[:"aria-labelledby"]
    assert_equal "印刷ステーションを削除", find("##{title}").text
    assert_text "『#{NAME}』を削除します。"
    assert_text "削除すると、このプリンターとの紐づけが解除され、元に戻せません。"
    assert_no_text "このステーションは現在オンラインです。" # オフラインのとき
    assert_selector "##{dialog_id} [aria-hidden=true]", text: "!"
    assert submit_button.disabled?
    assert_text "名前が一致するまで「削除する」は押せません。"
  end

  test "名前が一致するまで無効で、一致すると有効になりヒントが変わる／空白・全角・連続空白は一致、大文字小文字は不一致" do
    log_in_as_admin
    open_dialog
    fill_in input_id, with: "碩学館1F大部屋"
    assert submit_button.disabled?

    fill_in input_id, with: "a-bizhub551i"
    assert submit_button.disabled?
    fill_in input_id, with: "碩学館1F大部屋 a-bizhub551i" # 大文字小文字の違い
    assert submit_button.disabled?

    fill_in input_id, with: NAME
    assert_not submit_button.disabled?
    assert_text "名前が一致しました。「削除する」を押すと削除されます。"

    fill_in input_id, with: "  碩学館１Ｆ大部屋　　Ａ-bizhub551i  " # 前後の空白・全角英数・連続空白（全角含む）
    assert_not submit_button.disabled?
  end

  test "キャンセル・Esc・背景クリックで閉じ、削除されず、元の削除ボタンにフォーカスが戻る" do
    log_in_as_admin
    open_dialog
    click_on "キャンセル"
    assert_no_selector "##{dialog_id}[open]"
    assert_equal "削除", page.evaluate_script("document.activeElement.textContent.trim()")

    open_dialog
    find("##{input_id}").send_keys(:escape)
    assert_no_selector "##{dialog_id}[open]"
    assert_equal "削除", page.evaluate_script("document.activeElement.textContent.trim()")

    open_dialog
    page.execute_script("document.getElementById('#{dialog_id}').click()") # 背景（dialog 自身）のクリック
    assert_no_selector "##{dialog_id}[open]"

    assert PrintStation.exists?(@station.id)
  end

  test "Tab 順は 入力 → キャンセル → 削除する" do
    log_in_as_admin
    open_dialog
    fill_in input_id, with: NAME
    find("##{input_id}").send_keys(:tab)
    assert_equal "キャンセル", page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.action.send_keys(:tab).perform
    assert_equal "削除する", page.evaluate_script("document.activeElement.textContent.trim()")
  end

  test "一致して「削除する」を押すと、そのステーションだけが削除される" do
    log_in_as_admin
    open_dialog
    fill_in input_id, with: NAME
    submit_button.click
    assert_text "「#{NAME}」を削除しました。"
    assert_not PrintStation.exists?(@station.id)
    assert PrintStation.exists?(@other.id)
  end

  test "オンラインのときだけ「現在オンラインです」が出る" do
    @station.update!(last_seen_at: Time.current)
    log_in_as_admin
    assert @station.reload.online?
    open_dialog
    assert_text "このステーションは現在オンラインです。"
  end

  test "1440px で横スクロールが出ず、文字は小さくならない（本文18・ボタン19）" do
    log_in_as_admin
    page.driver.browser.manage.window.resize_to(1440, 1000)
    visit admin_print_stations_path
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    open_dialog
    assert_equal "18px", page.evaluate_script("getComputedStyle(document.querySelector('##{dialog_id} p')).fontSize")
    assert_equal "19px", page.evaluate_script("getComputedStyle(document.querySelector('##{dialog_id} button[type=submit]')).fontSize")
  end
end
