require "net/http"

# 小テスト用の単語帳を取り込む。市販の単語帳はリポジトリに置かないので、CSV は外から渡す。
#   WORDBOOK_SEED_PATH  ローカルの CSV のパス
#   WORDBOOK_SEED_URL   非公開ストレージの CSV の URL（署名付き URL など）
#   WORDBOOK_SEED_NAME  単語帳の名前（省略時「LEAP 改訂版」）
# どちらも無ければスキップする。同じ名前の単語帳がすでにあれば何もしない。
class WordbookSeed
  DEFAULT_NAME = "LEAP 改訂版".freeze
  MAX_REDIRECTS = 3

  def self.run(env: ENV, logger: $stdout, http: Net::HTTP) = new(env: env, logger: logger, http: http).run

  def initialize(env:, logger:, http:)
    @env = env
    @http = http
    @logger = logger
    @name = env["WORDBOOK_SEED_NAME"].presence || DEFAULT_NAME
  end

  # 戻り値: :exists / :skipped / :imported
  def run
    return :exists if Wordbook.exists?(name: @name)

    path = @env["WORDBOOK_SEED_PATH"].presence
    url = @env["WORDBOOK_SEED_URL"].presence
    unless path || url
      @logger.puts "単語帳: WORDBOOK_SEED_PATH / WORDBOOK_SEED_URL が無いので取り込みをスキップします"
      return :skipped
    end

    data = path ? File.binread(path) : fetch(URI(url))
    result = WordbookImporter.new(name: @name, data: data).call
    raise "#{@name} の取り込みに失敗しました: #{result.errors.join(' / ')}" unless result.success?

    @logger.puts "単語帳: #{@name} を #{result.created} 語取り込みました"
    :imported
  end

  private

  def fetch(uri, redirects = 0)
    raise ArgumentError, "WORDBOOK_SEED_URL は https:// で指定してください" unless uri.is_a?(URI::HTTPS)

    response = @http.get_response(uri)
    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection
      raise "WORDBOOK_SEED_URL のリダイレクトが多すぎます" if redirects >= MAX_REDIRECTS
      fetch(URI(response["location"]), redirects + 1)
    else
      # URL には署名が含まれうるのでエラーメッセージに出さない
      raise "WORDBOOK_SEED_URL の取得に失敗しました（HTTP #{response.code}）"
    end
  end
end
