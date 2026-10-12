require "rails_helper"

RSpec.describe GuestImport do
  let(:event) { create(:event, default_plus_ones: 1) }

  def import(text, **attrs)
    event.guest_imports.create!({ csv_data: text }.merge(attrs))
  end

  it "maps common header names, including first/last name columns" do
    rows = import("First Name,Last Name,E-mail Address,Mobile,Side,Plus-ones,Notes\nDana,Whitfield,DANA@example.com,(555) 010-2000,Bride,2,Vegan\n").rows
    expect(rows.sole).to have_attributes(status: :new)
    expect(rows.sole.attributes).to include(name: "Dana Whitfield", email: "DANA@example.com", phone: "(555) 010-2000",
      group_name: "Bride", plus_ones_allowed: 2, host_notes: "Vegan")
  end

  it "handles semicolon-separated files, a UTF-8 BOM and Windows-1252 text" do
    text = "﻿Name;Email\nJosé Núñez;jose@example.com\n"
    expect(import(text).rows.sole.attributes[:name]).to eq("José Núñez")

    latin = "Name,Email\nRen\xE9e Dubois,renee@example.com\n".dup.force_encoding("ASCII-8BIT")
    expect(import(latin).rows.sole.attributes[:name]).to eq("Renée Dubois")
  end

  it "reads headerless lists positionally and falls back to the email for a missing name" do
    rows = import("Lee Park, lee@example.com, , Work, yes\n, sam.moreno@example.com\n").rows
    expect(rows.first.attributes).to include(name: "Lee Park", email: "lee@example.com", group_name: "Work", plus_ones_allowed: 1)
    expect(rows.second.attributes).to include(name: "Sam Moreno", plus_ones_allowed: 1) # blank uses the event default
  end

  it "classifies new, invalid, duplicate-in-file and existing rows" do
    create(:guest, event: event, email: "existing@example.com", name: "Existing")
    rows = import(<<~CSV).rows
      Name,Email,Phone
      New Person,new@example.com,
      Bad Email,not-an-email,
      Again,new@example.com,
      Existing Updated,existing@example.com,+15550100
      Bad Phone,phone@example.com,12
    CSV
    expect(rows.map(&:status)).to eq(%i[new invalid duplicate_in_file exists invalid])
    expect(rows.second.messages.join).to include("Email is invalid")
  end

  it "applies new and updated rows, never touching RSVPs, then erases the raw data" do
    guest = create(:guest, event: event, email: "existing@example.com", name: "Old Name", rsvp_status: "yes", party_size: 1)
    gi = import("Name,Email,Group\nNew Person,new@example.com,Family\nNew Name,existing@example.com,Work\n", update_existing: true)

    summary = gi.apply!
    expect(summary).to eq("created" => 1, "updated" => 1, "skipped" => 0)
    expect(guest.reload).to have_attributes(name: "New Name", group_name: "Work", rsvp_status: "yes")
    expect(event.guests.find_by(email: "new@example.com")).to have_attributes(source: "csv", group_name: "Family")
    expect(gi.reload).to have_attributes(status: "completed", csv_data: nil)
    expect(event.activities.last.action).to eq("guests_imported")
  end

  it "rejects empty, malformed and oversized input" do
    expect(event.guest_imports.new(csv_data: "")).not_to be_valid
    expect(event.guest_imports.new(csv_data: "Name,Email\n\"unclosed,quote\n")).not_to be_valid
    big = "Name\n" + Array.new(GuestImport::MAX_ROWS + 1) { |i| "Guest #{i}" }.join("\n")
    expect(event.guest_imports.new(csv_data: big).tap(&:validate).errors[:base].join).to include("more than")
  end
end
