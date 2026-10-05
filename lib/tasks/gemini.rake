namespace :gemini do
  desc "このキー（GEMINI_API_KEY）で generateContent を呼べるモデルを一覧する。GEMINI_MODEL を決める・確認するときに使う"
  task models: :environment do
    abort "GEMINI_API_KEY が設定されていません。" unless GeminiConfig.configured?

    puts "現在の GEMINI_MODEL: #{GeminiConfig.model}"
    Gemini::Client.new.list_models.each { |name| puts name }
  end

  desc "画像ファイルを今の GEMINI_MODEL で構造化して JSON を表示する（モデル変更時の回帰確認）。FILES=a.jpg,b.png"
  task probe: :environment do
    abort "GEMINI_API_KEY が設定されていません。" unless GeminiConfig.configured?

    files = ENV.fetch("FILES") { abort "FILES=画像のパス（カンマ区切り）を指定してください。" }.split(",").map(&:strip)
    puts "モデル: #{GeminiConfig.model}"
    files.each do |path|
      mime = Upload.sniff_content_type(path) or abort "#{path}: JPEG か PNG ではありません。"
      raw = Gemini::Client.new.generate(File.binread(path), mime_type: mime)
      puts "--- #{path}", JSON.pretty_generate(JSON.parse(raw))
    end
  end
end
