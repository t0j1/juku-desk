require "test_helper"

class WordbookImporterTest < ActiveSupport::TestCase
  def import(csv, name: "新しい単語帳", overwrite: false)
    WordbookImporter.new(name: name, data: csv, overwrite: overwrite).call
  end

  test "imports a UTF-8 CSV (with BOM)" do
    result = import("﻿No,単語,意味\n1,agree,[自] ①賛成する\n2,oppose,[他] ～に反対する\n")
    assert result.success?
    assert_equal [ 2, 0 ], [ result.created, result.updated ]
    assert_equal 2, result.wordbook.words_count
    assert_equal "oppose", result.wordbook.words.find_by(number: 2).term
  end

  test "seed CSV has 50 words numbered 1 to 50" do
    result = import(File.binread(Rails.root.join("db/seeds/leap_modified_list.csv")), name: "LEAP seed")
    assert result.success?, result.errors.inspect
    assert_equal [ 1, 50, 50 ], [ result.wordbook.min_number, result.wordbook.max_number, result.wordbook.words_count ]
  end

  test "rejects a wrong header" do
    result = import("番号,単語,意味\n1,a,b\n")
    assert_not result.success?
    assert_match(/ヘッダー/, result.errors.first)
    assert_nil Wordbook.find_by(name: "新しい単語帳")
  end

  test "rejects numbers duplicated inside the file" do
    result = import("No,単語,意味\n1,a,あ\n1,b,い\n")
    assert_not result.success?
    assert_match(/重複/, result.errors.join)
  end

  test "rejects numbers already registered unless overwrite is chosen" do
    result = import("No,単語,意味\n1,changed,変更\n", name: wordbooks(:leap).name)
    assert_not result.success?
    assert_match(/すでに登録/, result.errors.join)
    assert_equal "word1", words(:leap_1).reload.term
  end

  test "overwrite replaces the same number and keeps the others" do
    result = import("No,単語,意味\n1,changed,変更\n51,extra,追加\n", name: wordbooks(:leap).name, overwrite: true)
    assert result.success?
    assert_equal [ 1, 1 ], [ result.created, result.updated ]
    assert_equal "changed", words(:leap_1).reload.term
    assert_equal 51, wordbooks(:leap).reload.words_count
  end

  test "rejects invalid encoding and bad rows" do
    assert_not import("No,単語,意味\n1,a,\xFF\n".b).success?
    result = import("No,単語,意味\nx,a,あ\n2,,い\n")
    assert_not result.success?
    assert_equal 2, result.errors.size
  end
end
