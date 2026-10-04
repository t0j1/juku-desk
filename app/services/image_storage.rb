require "fileutils"

# マーキング検出で扱う画像（元画像と切り出し）の置き場所。R2_BUCKET があれば Cloudflare R2（PdfStorage::R2 と同じ方式）、
# なければ開発・テスト用にローカルディスク。本番（Render Free はファイルが消える）でローカルには置かない。
# 画像はデコードせず、ファイルのままストリーミングで渡す。
module ImageStorage
  class NotConfigured < StandardError; end

  module_function

  def put_file(key, path, content_type:)
    if r2?
      PdfStorage.r2.put_file(key, path, content_type:)
    else
      target = disk_path(key)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(path, target)
    end
    key
  end

  def read(key)
    r2? ? PdfStorage.r2.read(key) : File.binread(disk_path(key))
  end

  def delete(keys)
    keys = Array(keys).compact
    return if keys.empty?

    if r2? then PdfStorage.r2.delete(keys)
    else keys.each { |k| FileUtils.rm_f(disk_path(k)) }
    end
  end

  def r2? = ENV["R2_BUCKET"].present?

  def disk_root
    Pathname(ENV["MARKING_DISK_PATH"].presence || Rails.root.join(Rails.env.test? ? "tmp/marking_test" : "storage/marking"))
  end

  def disk_path(key)
    raise NotConfigured, "画像の保存先（R2_BUCKET など）が設定されていません" if Rails.env.production?
    raise ArgumentError, "不正なキーです" if key.include?("..")

    disk_root.join(key).to_s
  end
end
