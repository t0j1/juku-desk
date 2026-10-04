module Internal
  # schedule-web（Supabase のトリガー / Edge Function）からの通知を受ける。ログインではなく HMAC 署名で認証する。
  class ScheduleEventsController < ApplicationController
    allow_unauthenticated_access
    allow_viewer_writes
    allow_without_two_factor
    skip_forgery_protection

    def create
      return head :service_unavailable unless ScheduleEventSignature.secret

      payload = JSON.parse(request.raw_post)
      return head :unauthorized unless payload.is_a?(Hash) &&
        ScheduleEventSignature.valid?(request.headers["X-Schedule-Timestamp"], payload, request.headers["X-Schedule-Signature"])

      ScheduleEvents.handle(payload)
      head :no_content
    rescue JSON::ParserError, ScheduleEvents::Invalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
