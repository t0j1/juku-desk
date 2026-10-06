require "test_helper"

class DriverPresetTest < ActiveSupport::TestCase
  test "a listed name or a blank passes; the form value is trimmed" do
    assert_nil DriverPreset.resolve("")
    assert_equal "A4両面", DriverPreset.resolve(" A4両面 ")
  end

  test "a name that is not in the list is rejected" do
    assert_raises(ArgumentError) { DriverPreset.resolve("デフォルト") }
  end

  test "the value already saved on the record is kept even if it is not in the list" do
    assert_equal "bizhub-551i", DriverPreset.resolve("bizhub-551i", keep: "bizhub-551i")
    assert_raises(ArgumentError) { DriverPreset.resolve("bizhub-551i", keep: "other-old") }
  end

  test "adding a new name saves it to the list" do
    assert_difference -> { DriverPreset.count }, 1 do
      assert_equal "新設定", DriverPreset.resolve(DriverPreset::NEW, " 新設定 ")
    end
    assert_equal "新設定", DriverPreset.listed.last.name
  end

  test "a new name that is blank, over 100 characters or already listed is rejected" do
    assert_raises(ArgumentError) { DriverPreset.resolve(DriverPreset::NEW, "  ") }
    assert_raises(ArgumentError) { DriverPreset.resolve(DriverPreset::NEW, "あ" * 101) }
    assert_raises(ArgumentError) { DriverPreset.resolve(DriverPreset::NEW, "A4両面") }
    assert_equal "あ" * 100, DriverPreset.resolve(DriverPreset::NEW, "あ" * 100)
  end
end
