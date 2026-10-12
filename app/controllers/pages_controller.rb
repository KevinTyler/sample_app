class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    resume_session
    @templates = InvitationTemplate.all.first(6)
  end

  def about
  end

  def contact
  end
end
