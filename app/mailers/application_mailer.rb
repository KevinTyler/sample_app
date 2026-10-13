class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Cordially <invitations@cordially.localhost>") }
  layout "mailer"
end
