class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Larkspur <invitations@larkspur.localhost>") }
  layout "mailer"
end
