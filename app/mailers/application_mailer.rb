class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "from@example.com")
  layout "mailer"

  private
    # MailTemplate の文面でメールを作る。text は本文そのまま、html は本文を HTML エスケープして改行とリンクだけ反映する。
    def template_mail(key, user, url:, expires:)
      rendered = MailTemplate.for(key).render("name" => user.name, "url" => url, "expires" => expires)
      @html_body = html_from(rendered.body, url)
      mail(to: user.email_address, subject: rendered.subject) do |format|
        format.text { render plain: rendered.body }
        format.html { render html: @html_body, layout: "mailer" }
      end
    end

    def html_from(text, url)
      escaped = ERB::Util.html_escape(text)
      linked = escaped.gsub(ERB::Util.html_escape(url)) { view_context.link_to(ERB::Util.html_escape(url), url) }
      view_context.simple_format(linked, {}, sanitize: false)
    end
end
