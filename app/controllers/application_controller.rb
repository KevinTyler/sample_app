class ApplicationController < ActionController::Base
  include Authentication

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

  private
    def current_user
      Current.user
    end
end
