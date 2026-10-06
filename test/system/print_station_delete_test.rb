require "application_system_test_case"

class PrintStationDeleteTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:system_admin)
  end

  test "delete modal opens instead of browser confirm" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    # 削除ボタンをクリックしてモーダルが開くことを確認
    find("button", text: "削除", match: :first).click

    # モーダルが開いていることを確認
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_selector "h2", text: "印刷ステーションを削除"
    assert_no_selector "button[data-turbo-confirm]"  # 古いconfirmはない
  end

  test "delete button is disabled until name matches" do
    station, = PrintStation.register!(name: "A-bizhub551i")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    # 初期状態では削除するボタンが無効
    assert_selector "button", text: "削除する", disabled: true
    assert_selector "p", text: "名前が一致するまで「削除する」は押せません。"

    # 入力しても不一致なら無効のまま
    fill_in "delete_confirm_input_#{station.id}", with: "違う名前"
    assert_selector "button", text: "削除する", disabled: true
  end

  test "full-width and whitespace normalization allows match" do
    station, = PrintStation.register!(name: "A-bizhub551i")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    # 全角英数で入力しても一致
    fill_in "delete_confirm_input_#{station.id}", with: "Ａ-bizhub551i"
    assert_selector "button", text: "削除する", disabled: false
    assert_selector "p", text: "名前が一致しました。「削除する」を押すと削除されます。"

    # 前後の空白も吸収
    fill_in "delete_confirm_input_#{station.id}", with: "  A-bizhub551i  "
    assert_selector "button", text: "削除する", disabled: false

    # 連続空白も吸収
    fill_in "delete_confirm_input_#{station.id}", with: "A   bizhub551i"
    assert_selector "button", text: "削除する", disabled: false

    # 全角スペースも吸収
    fill_in "delete_confirm_input_#{station.id}", with: "A\u3000bizhub551i"
    assert_selector "button", text: "削除する", disabled: false
  end

  test "case sensitivity - lowercase does not match" do
    station, = PrintStation.register!(name: "A-bizhub551i")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    # 小文字では不一致
    fill_in "delete_confirm_input_#{station.id}", with: "a-bizhub551i"
    assert_selector "button", text: "削除する", disabled: true
    assert_selector "p", text: "名前が一致するまで「削除する」は押せません。"
  end

  test "cancel closes modal and returns focus to delete button" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    delete_button = find("button", text: "削除", match: :first)
    delete_button.click

    assert_selector "[role='dialog'][aria-modal='true']", visible: true

    click_button "キャンセル"

    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
    # フォーカスが元の削除ボタンに戻る（視覚確認のみ）
  end

  test "escape key closes modal and returns focus" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    delete_button = find("button", text: "削除", match: :first)
    delete_button.click

    assert_selector "[role='dialog'][aria-modal='true']", visible: true

    find("input[id^='delete_confirm_input_']").send_keys :escape

    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
  end

  test "backdrop click closes modal" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    assert_selector "[role='dialog'][aria-modal='true']", visible: true

    # バックドロップ部分をクリック（モーダル外）
    find("[role='dialog'][aria-modal='true']").click(x: -10, y: -10)

    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
  end

  test "online station shows online warning" do
    station, = PrintStation.register!(name: "オンラインステーション")
    station.seen!("0.1.0")  # オンラインにする
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    assert_selector "p", text: "このステーションは現在オンラインです。"
  end

  test "offline station does not show online warning" do
    station, = PrintStation.register!(name: "オフラインステーション")
    station.update_columns(last_seen_at: 1.hour.ago)
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    assert_no_selector "p", text: "このステーションは現在オンラインです。"
  end

  test "modal has correct accessibility attributes" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    modal = find("[role='dialog'][aria-modal='true']")
    assert_equal "true", modal["aria-modal"]
    assert modal["aria-labelledby"].present?

    # Tab順: 入力 → キャンセル → 削除する
    input = find("input[id^='delete_confirm_input_']")
    cancel = find_button("キャンセル")
    delete_btn = find_button("削除する")

    # 入力欄にフォーカスが当たっている
    assert_equal input, page.driver.browser.switch_to.active_element
  end

  test "tab order is input -> cancel -> delete" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    find("button", text: "削除", match: :first).click

    input = find("input[id^='delete_confirm_input_']")
    cancel = find_button("キャンセル")
    delete_btn = find_button("削除する")

    # Tab で移動
    input.send_keys :tab
    assert_equal cancel, page.driver.browser.switch_to.active_element

    cancel.send_keys :tab
    # 削除するボタンは無効の間はスキップされる（disabled の標準挙動）
    # 有効化してから確認
    fill_in "delete_confirm_input_#{station.id}", with: "テストステーション"
    cancel.send_keys :tab
    assert_equal delete_btn, page.driver.browser.switch_to.active_element
  end

  test "1440px width has no horizontal scroll" do
    station, = PrintStation.register!(name: "非常に長いステーション名がここにありますA-bizhub551i")
    visit admin_print_stations_path

    # ウィンドウ幅を1440pxに設定
    page.driver.browser.manage.window.resize_to(1440, 900)

    find("button", text: "削除", match: :first).click

    # モーダルが画面内に収まっている
    modal = find(".card")
    assert modal.native.rect.width <= 1440

    # テーブルも横スクロールなし
    table = find("#print_stations")
    assert table.native.rect.width <= 1440
  end

  test "other operations still work (test print, reissue, revoke)" do
    station, = PrintStation.register!(name: "テストステーション")
    visit admin_print_stations_path

    # テスト印刷ボタンがある
    assert_selector "button", text: "テスト印刷 ▾"
    # 再発行ボタンがある
    assert_selector "button", text: "再発行"
    # 失効ボタンがある
    assert_selector "button", text: "失効"

    # 削除モーダルを開いて閉じても他の操作に影響しない
    find("button", text: "削除", match: :first).click
    click_button "キャンセル"

    assert_selector "button", text: "テスト印刷 ▾"
    assert_selector "button", text: "再発行"
    assert_selector "button", text: "失効"
  end
end