# The host's address book: everyone they've invited, reusable for the next event.
class ContactsController < ApplicationController
  PER_PAGE = 100

  before_action :set_contact, only: %i[edit update destroy]

  def index
    @query = params[:q].to_s.strip
    contacts = Current.user.contacts.alphabetical
    contacts = contacts.search(@query) if @query.present?
    @total = Current.user.contacts.count
    @page = [ params[:page].to_i, 1 ].max
    @total_pages = [ (contacts.count / PER_PAGE.to_f).ceil, 1 ].max
    @contacts = contacts.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  def new
    @contact = Current.user.contacts.new
  end

  def create
    @contact = Current.user.contacts.new(contact_params)
    if @contact.save
      redirect_to contacts_path, notice: "#{@contact.name} added to your contacts."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to contacts_path, notice: "#{@contact.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @contact.destroy!
    redirect_to contacts_path, notice: "#{@contact.name} removed from your contacts. Guest lists aren't affected.", status: :see_other
  end

  def export
    csv = CSV.generate do |rows|
      rows << [ "Name", "Email", "Phone", "Household", "Notes" ]
      Current.user.contacts.alphabetical.each do |c|
        rows << CsvSafety.row([ c.name, c.email, c.phone, c.household, c.notes ])
      end
    end
    send_data csv, filename: "cordially-contacts-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  private
    def set_contact
      @contact = Current.user.contacts.find(params[:id])
    end

    def contact_params
      params.expect(contact: %i[name email phone household notes])
    end
end
