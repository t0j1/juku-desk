# 単語帳の登録（管理者のみ）。CSV をアップロードして取り込む
class WordbooksController < ApplicationController
  before_action :require_admin!

  def index
    @wordbooks = Wordbook.order(:name)
  end

  def create
    file = params[:file]
    result = WordbookImporter.new(name: params[:name], data: file&.read, overwrite: params[:overwrite] == "1").call
    if file.nil?
      @errors = [ "CSV ファイルを選んでください" ]
    elsif result.success?
      AuditLog.record!(:create, result.wordbook, metadata: { wordbook: result.wordbook.name, created: result.created, updated: result.updated })
      return redirect_to wordbooks_path, notice: "「#{result.wordbook.name}」を取り込みました（新規#{result.created}語、上書き#{result.updated}語）。", status: :see_other
    else
      @errors = result.errors
    end
    @wordbooks = Wordbook.order(:name)
    render :index, status: :unprocessable_entity
  end
end
