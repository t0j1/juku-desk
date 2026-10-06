require "test_helper"

class PrintPresetTest < ActiveSupport::TestCase
  test "validates presence of name" do
    preset = PrintPreset.new(name: "")
    assert_not preset.valid?
    assert_includes preset.errors[:name], "を入力してください"
  end

  test "validates uniqueness of name" do
    PrintPreset.create!(name: "テストプリセット")
    preset = PrintPreset.new(name: "テストプリセット")
    assert_not preset.valid?
    assert_includes preset.errors[:name], "はすでに存在します"
  end

  test "validates maximum length of name" do
    preset = PrintPreset.new(name: "a" * 101)
    assert_not preset.valid?
    assert_includes preset.errors[:name], "は 100 文字以内で入力してください"
  end

  test "for_select returns ordered presets" do
    PrintPreset.create!(name: "プリセットC")
    PrintPreset.create!(name: "プリセットA")
    PrintPreset.create!(name: "プリセットB")

    options = PrintPreset.for_select
    assert_equal ["プリセットA", "プリセットB", "プリセットC", "新しく追加する"], options.map(&:first)
    assert_equal ["プリセットA", "プリセットB", "プリセットC", "__new__"], options.map(&:last)
  end

  test "for_select with with_default: true includes '(既定を使う)' at start" do
    PrintPreset.create!(name: "プリセットA")

    options = PrintPreset.for_select(with_default: true)
    assert_equal ["(既定を使う)", "プリセットA", "新しく追加する"], options.map(&:first)
    assert_equal ["", "プリセットA", "__new__"], options.map(&:last)
  end

  test "for_select with current_value not in list includes it as '現在の値'" do
    PrintPreset.create!(name: "プリセットA")

    options = PrintPreset.for_select(current_value: "古いプリセット")
    assert_equal ["古いプリセット （現在の値）", "プリセットA", "新しく追加する"], options.map(&:first)
    assert_equal ["古いプリセット", "プリセットA", "__new__"], options.map(&:last)
  end

  test "for_select with current_value in list does not duplicate" do
    PrintPreset.create!(name: "プリセットA")

    options = PrintPreset.for_select(current_value: "プリセットA")
    assert_equal ["プリセットA", "新しく追加する"], options.map(&:first)
  end

  test "add_new! creates new preset" do
    assert_difference "PrintPreset.count", 1 do
      PrintPreset.add_new!("新しいプリセット")
    end
    assert PrintPreset.exists?(name: "新しいプリセット")
  end

  test "add_new! strips whitespace" do
    PrintPreset.add_new!("  スペースあり  ")
    assert PrintPreset.exists?(name: "スペースあり")
  end

  test "add_new! raises on blank name" do
    assert_raises ArgumentError, "プリセット名を入力してください" do
      PrintPreset.add_new!("")
    end
    assert_raises ArgumentError, "プリセット名を入力してください" do
      PrintPreset.add_new!("   ")
    end
  end

  test "add_new! raises on too long name" do
    assert_raises ArgumentError, "プリセット名は 100 文字以内で入力してください" do
      PrintPreset.add_new!("a" * 101)
    end
  end

  test "add_new! raises on duplicate name" do
    PrintPreset.create!(name: "既存プリセット")
    assert_raises ArgumentError, "そのプリセット名はすでに存在します" do
      PrintPreset.add_new!("既存プリセット")
    end
  end
end
