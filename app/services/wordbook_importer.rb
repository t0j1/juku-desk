require "csv"

# 単語帳 CSV（ヘッダー No,単語,意味 / UTF-8）を取り込む。
# 番号が重複していたらエラー。overwrite: true のときだけ、登録済みの同じ番号を上書きする。
class WordbookImporter
  HEADERS = %w[No 単語 意味].freeze
  MAX_ERRORS = 10

  Result = Struct.new(:wordbook, :created, :updated, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def initialize(name:, data:, overwrite: false)
    @name = name.to_s.strip
    @data = data.to_s.b
    @overwrite = overwrite
  end

  def call
    errors = []
    errors << "単語帳の名前を入力してください" if @name.blank?
    rows = parse(errors)
    return failure(errors) if errors.any?

    wordbook = Wordbook.find_or_initialize_by(name: @name)
    existing = wordbook.persisted? ? wordbook.words.where(number: rows.map { |r| r[:number] }).pluck(:number) : []
    if existing.any? && !@overwrite
      errors << "すでに登録されている番号があります（#{summarize(existing)}）。上書きする場合は「同じ番号を上書きする」を選んでください"
      return failure(errors)
    end

    Wordbook.transaction do
      wordbook.save!
      Word.upsert_all(rows.map { |r| r.merge(wordbook_id: wordbook.id) }, unique_by: %i[wordbook_id number])
      Wordbook.reset_counters(wordbook.id, :words)
    end
    Result.new(wordbook: wordbook.reload, created: rows.size - existing.size, updated: existing.size, errors: [])
  end

  private
    def parse(errors)
      text = @data.force_encoding(Encoding::UTF_8)
      unless text.valid_encoding?
        errors << "UTF-8 で保存した CSV を選んでください"
        return []
      end

      table = CSV.parse(text.delete_prefix("﻿"), headers: true)
      unless table.headers == HEADERS
        errors << "ヘッダーは「#{HEADERS.join(',')}」にしてください"
        return []
      end

      rows = []
      table.each.with_index(2) do |row, line|
        number = Integer(row["No"].to_s.strip, exception: false)
        term = row["単語"].to_s.strip
        meaning = row["意味"].to_s.strip
        if number.nil? || number <= 0 || term.blank? || meaning.blank?
          errors << "#{line}行目: 番号（正の整数）、単語、意味をすべて入力してください"
        else
          rows << { number: number, term: term, meaning: meaning }
        end
      end
      errors << "CSV に単語がありません" if rows.empty? && errors.empty?

      duplicates = rows.group_by { |r| r[:number] }.select { |_, v| v.size > 1 }.keys
      errors << "CSV 内で番号が重複しています（#{summarize(duplicates)}）" if duplicates.any?
      errors.first(MAX_ERRORS).tap { |kept| errors.replace(kept) }
      rows
    rescue CSV::MalformedCSVError => e
      errors << "CSV を読み取れませんでした（#{e.message}）"
      []
    end

    def summarize(numbers)
      shown = numbers.sort.first(5).map { |n| "No.#{n}" }.join("、")
      numbers.size > 5 ? "#{shown} ほか#{numbers.size - 5}件" : shown
    end

    def failure(errors)
      Result.new(wordbook: nil, created: 0, updated: 0, errors: errors)
    end
end
