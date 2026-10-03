class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  # No browser-version gate: classroom iPads run older iOS Safari (the :modern preset needs Safari 17.2+
  # and blocked the QR print page with 406 "Your browser is not supported").

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
