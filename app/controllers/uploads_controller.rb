# マーキング検出：教材画像（ブラウザで縮小・赤枠検出済み）と、切り出した領域の保存。
# サーバーでは画像をデコードしない（種類は先頭バイト、寸法はブラウザの申告、sha256 はストリーミングで計算）。
class UploadsController < ApplicationController
  before_action :require_writer!, only: :new

  def index
    @uploads = Upload.includes(:user, :crop_regions).order(created_at: :desc).limit(100)
  end

  def new
    @config = MarkingConfig.to_h
  end

  def show
    @upload = Upload.find(params[:id])
    @regions = @upload.crop_regions.order(:id)
  end

  # 構造化の開始・やり直し（confirmed / failed / model_unavailable と、処理中のまま止まった領域を順番待ちに積む）。API キー設定前に取り込んだ画像用
  def extract
    upload = Upload.find(params[:id])
    return redirect_to upload_path(upload), alert: "GEMINI_API_KEY が設定されていません。" unless GeminiConfig.configured?

    regions = upload.crop_regions
    count = Marking::Enqueuer.call(regions.where(status: CropRegion::RETRYABLE_STATUSES).or(regions.stale_processing))
    redirect_to upload_path(upload), notice: "#{count} 件を構造化の順番待ちに入れました。", status: :see_other
  end

  def image
    upload = Upload.find(params[:id])
    send_image upload.r2_key, upload.content_type
  end

  # 1 枚ぶん（元画像 + 確定した領域とその切り出し）を受け取る。同じ sha256 の画像は取り込み直さず、既存を返す
  def create
    file = params[:image]
    return render_error("画像ファイルがありません。") unless file.respond_to?(:tempfile)
    return render_error("画像は #{MarkingConfig.max_bytes / 1.megabyte}MB 以下にしてください。", :content_too_large) if file.size > MarkingConfig.max_bytes

    content_type = Upload.sniff_content_type(file.tempfile.path)
    return render_error("JPEG か PNG の画像だけ取り込めます。", :unsupported_media_type) unless content_type

    sha256 = Digest::SHA256.file(file.tempfile.path).hexdigest
    if (existing = Upload.find_by(sha256:))
      return render json: { id: existing.id, duplicate: true, regions: existing.crop_regions.count, url: upload_path(existing) }
    end

    regions = region_params
    error = region_error(regions)
    return render_error(error) if error

    upload = save_upload(file, content_type, sha256, regions)
    Marking::Enqueuer.call(upload.crop_regions) # 構造化は順番待ちに積むだけ（すぐ返す）
    render json: { id: upload.id, duplicate: false, regions: upload.crop_regions.size, url: upload_path(upload) }, status: :created
  rescue ActiveRecord::RecordNotUnique
    existing = Upload.find_by!(sha256:)
    render json: { id: existing.id, duplicate: true, regions: existing.crop_regions.count, url: upload_path(existing) }
  end

  private
    # viewer は閲覧だけ（取り込み画面は開かせない）
    def require_writer!
      redirect_to uploads_path, alert: "閲覧のみの権限では取り込めません。" unless current_user.can_write?
    end

    def save_upload(file, content_type, sha256, regions)
      keys = []
      Upload.transaction do
        upload = Upload.new(user: current_user, sha256:, content_type:, byte_size: file.size,
                            width: params[:width].to_i, height: params[:height].to_i,
                            r2_key: Upload.object_key(sha256, content_type))
        upload.save!
        keys << ImageStorage.put_file(upload.r2_key, file.tempfile.path, content_type:)
        regions.each_with_index do |region, index|
          key = CropRegion.object_key(sha256, index)
          keys << ImageStorage.put_file(key, region[:image].tempfile.path, content_type: "image/jpeg")
          upload.crop_regions.create!(bbox: region[:bbox], confidence: region[:confidence], r2_key: key, status: :confirmed)
        end
        AuditLog.record!(:create, upload, metadata: { resource: "Upload", regions: regions.size, bytes: file.size })
        upload
      end
    rescue StandardError
      ImageStorage.delete(keys) # 途中で失敗したら、置いてしまった画像を消す
      raise
    end

    # regions[0][bbox]（JSON）, regions[0][confidence], regions[0][image]（切り出し）
    def region_params
      raw = params[:regions]
      return [] unless raw.respond_to?(:keys)

      raw.keys.sort_by(&:to_i).map do |key|
        region = raw[key]
        bbox = JSON.parse(region[:bbox].to_s)
        bbox = bbox.slice("x", "y", "w", "h", "angle", "manual") if bbox.is_a?(Hash)
        { bbox: bbox, confidence: region[:confidence].presence&.to_f, image: region[:image] }
      rescue JSON::ParserError
        { bbox: nil, image: nil }
      end
    end

    def region_error(regions)
      return "領域が多すぎます（最大 #{MarkingConfig.max_regions} 件）。" if regions.size > MarkingConfig.max_regions

      regions.each do |r|
        return "領域の座標が正しくありません。" unless r[:bbox].is_a?(Hash)
        return "切り出し画像がありません。" unless r[:image].respond_to?(:tempfile)
        return "切り出し画像が大きすぎます。" if r[:image].size > MarkingConfig.max_bytes
        return "切り出し画像は JPEG か PNG にしてください。" unless Upload.sniff_content_type(r[:image].tempfile.path)
      end
      nil
    end

    def send_image(key, content_type)
      expires_in 1.hour, public: false
      send_data ImageStorage.read(key), type: content_type, disposition: "inline"
    end

    def render_error(message, status = :unprocessable_entity)
      render json: { error: message }, status: status
    end
end
