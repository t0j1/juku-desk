class Current < ActiveSupport::CurrentAttributes
  attribute :session, :ip_address
  delegate :user, to: :session, allow_nil: true
end
