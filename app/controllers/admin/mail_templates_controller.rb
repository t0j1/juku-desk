module Admin
  # パスワードリセット・招待メールの件名と本文を編集・プレビューする。
  class MailTemplatesController < BaseController
    before_action :set_template, only: %i[ edit update preview reset ]

    def index
      @templates = MailTemplate::KEYS.map { |key| MailTemplate.for(key) }
    end

    def edit
    end

    # 保存せずに、いまの入力を見本の値で描画して見せる
    def preview
      @template.assign_attributes(template_params)
      @rendered = @template.render(@template.sample_vars)
      @valid = @template.valid?
      render :edit
    end

    def update
      @template.assign_attributes(template_params.merge(updated_by: current_user))
      if @template.save
        AuditLog.record!(:mail_template_update, @template, metadata: { key: @template.key })
        redirect_to admin_mail_templates_path, notice: "#{@template.label}の文面を保存しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def reset
      MailTemplate.reset!(@template.key)
      AuditLog.record!(:mail_template_reset, nil, metadata: { key: @template.key })
      redirect_to admin_mail_templates_path, notice: "#{@template.label}の文面を初期値に戻しました。", status: :see_other
    end

    private
      def set_template
        raise ActiveRecord::RecordNotFound unless MailTemplate::KEYS.include?(params[:key])

        @template = MailTemplate.for(params[:key])
      end

      def template_params
        params.expect(mail_template: %i[ subject body ])
      end
  end
end
