require "application_system_test_case"

class MarkingTest < ApplicationSystemTestCase
  setup do
    Capybara.enable_aria_label = true # 領域ごとの入力欄・削除ボタンは aria-label で区別している
    @dir = Dir.mktmpdir
    ENV["MARKING_DISK_PATH"] = File.join(@dir, "store")
    page.driver.browser.manage.window.resize_to(1400, 1000)
    visit new_session_path
    fill_in "メールアドレス", with: users(:staff).email_address
    fill_in "パスワード", with: "password"
    click_on "ログイン"
    assert_selector "#students"
    visit new_upload_path
  end

  teardown do
    Capybara.enable_aria_label = false
    ENV.delete("MARKING_DISK_PATH")
    FileUtils.rm_rf(@dir)
  end

  def attach_image(path)
    attach_file "marking-files", path, visible: :all
  end

  def set_field(label, value)
    field = find_field(label)
    field.set(value.to_s)
  end

  test "detect, delete, adjust, add, confirm: saved exactly as edited, and a second upload of the same image is not stored again" do
    path = write_marking_png("three.png", frames: [ [ 40, 50, 260, 150 ], [ 400, 60, 300, 180 ], [ 150, 350, 450, 200 ] ], filled: [ [ 650, 450, 100, 100 ] ])
    attach_image path
    assert_text "赤枠を 3 件検出しました"
    assert_selector "[data-region-row]", count: 3
    page.save_screenshot(Rails.root.join("tmp/marking_preview.png").to_s) if ENV["SCREENSHOTS"]

    # 削除（領域 3）→ 2 件、調整（領域 1 の左を 123 に）、手動追加 → 3 件
    click_on "領域 3 を削除"
    assert_selector "[data-region-row]", count: 2
    set_field "領域 1 の 左", 123
    click_on "領域を追加"
    assert_selector "[data-region-row]", count: 3
    assert_selector "[data-box]", count: 3

    click_on "確定して保存"
    assert_text "保存しました（領域 3 件）"

    assert_equal 1, Upload.count
    upload = Upload.first
    assert_equal [ 800, 600 ], [ upload.width, upload.height ]
    regions = upload.crop_regions.order(:id).to_a
    assert_equal 3, regions.size
    assert_equal %w[confirmed], regions.map(&:status).uniq
    assert_equal 1, regions.count { |r| r.bbox["manual"] }
    assert_equal 1, regions.count { |r| r.bbox["x"] == 123 }, regions.map(&:bbox).inspect
    auto = regions.reject { |r| r.bbox["manual"] }
    assert_equal 2, auto.size
    assert auto.all? { |r| r.confidence.to_f > 0.5 }
    assert regions.all? { |r| File.size(ImageStorage.disk_path(r.r2_key)) > 100 } # 切り出し画像が保存されている

    # 同じ画像をもう一度：uploads は 1 件のまま
    visit new_upload_path
    attach_image path
    assert_text "赤枠を 3 件検出しました"
    click_on "確定して保存"
    assert_text "取り込み済みの画像でした"
    assert_equal 1, Upload.count
    assert_equal 3, CropRegion.count
  end

  test "an image with no red frame can still proceed by adding a region by hand" do
    attach_image write_marking_png("none.png", frames: [], seed: 7)
    assert_text "赤枠が見つかりませんでした"
    assert_selector "[data-region-row]", count: 0
    assert_button "確定して保存", disabled: true

    click_on "領域を追加"
    assert_selector "[data-region-row]", count: 1
    click_on "確定して保存"
    assert_text "保存しました（領域 1 件）"
    assert_equal 1, Upload.count
    assert_equal true, CropRegion.last.bbox["manual"]
  end

  test "a filled red shape and a frame around the whole image are not detected" do
    attach_image write_marking_png("traps.png", frames: [ [ 0, 0, 800, 600 ] ], filled: [ [ 200, 200, 250, 150 ] ], seed: 9)
    assert_text "赤枠が見つかりませんでした"
  end

  test "several images at once each get their own preview" do
    attach_file "marking-files", [ write_marking_png("a.png", frames: [ [ 100, 100, 300, 200 ] ], seed: 1), write_marking_png("b.png", frames: [ [ 50, 60, 200, 150 ], [ 400, 300, 250, 200 ] ], seed: 2) ], visible: :all
    assert_selector "[data-item]", count: 2
    assert_text "赤枠を 1 件検出しました"
    assert_text "赤枠を 2 件検出しました"
    click_on "確定して保存"
    assert_text "2 枚を保存しました"
    assert_equal 2, Upload.count
  end
end
