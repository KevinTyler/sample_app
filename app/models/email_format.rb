# Stricter than URI::MailTo::EMAIL_REGEXP: the domain must contain a dot ("dana@example" is
# almost always a typo in a guest list, and can't receive mail from the internet anyway).
module EmailFormat
  REGEXP = /\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+\z/
end
