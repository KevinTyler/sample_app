# "Switching from Paperless Post": bring your people (with the replies you've collected) and your
# usual settings over in one place. Works the same for any other service that exports a spreadsheet.
class SwitchesController < ApplicationController
  def show
    @user = Current.user
    @recent = Current.user.contact_imports.where(status: "completed").order(updated_at: :desc).limit(5)
  end
end
