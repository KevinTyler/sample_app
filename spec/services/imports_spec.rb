require "rails_helper"

RSpec.describe "Reading guest lists and contacts from anywhere" do
  def people_from(data, filename: nil, country_code: "1")
    Imports::People.new(Imports::Reader.read(data, filename: filename), country_code: country_code)
  end

  describe "a Paperless-Post-style guest list spreadsheet (.xlsx)" do
    let(:workbook) do
      xlsx_from([
        [ "Guest list: Maya turns thirty" ],
        [ "Name", "Email", "Status", "# Attending", "Kids", "Group", "Address 1", "City", "State", "Zip", "Message", "Table #" ],
        [ "Dana Whitfield", "dana@example.com", "Attending", 3, 1, "Family", "12 Garden St", "Brooklyn", "NY", "11201", "Can't wait!", 4 ],
        [ "Lee Park", "lee@example.com", "Not Attending", 0, nil, "Work", nil, nil, nil, nil, nil, nil ],
        [ "Sam Ortiz", "sam@example.com", "No Reply", nil, nil, "Work", nil, nil, nil, nil, nil, nil ],
        [ "Priya Shah", "priya@example.com", "Maybe", 2, nil, nil, nil, nil, nil, nil, nil, nil ],
        [ "Dana W.", "DANA@example.com", "", nil, nil, nil, nil, nil, nil, nil, nil, nil ]
      ])
    end

    it "finds the headings under a title row and reads every column it understands" do
      people = people_from(workbook, filename: "export (2).xlsx")

      expect(people.mapping.values).to contain_exactly("name", "email", "rsvp", "party_size", "kids", "group", "address_line1", "city", "region", "postal_code", "notes")
      expect(people.skipped_columns).to eq([ "Table #" ])
      expect(people.title_hint).to eq("Maya turns thirty")
      expect(people.has_replies?).to be(true)

      dana = people.people.find { |p| p.email == "dana@example.com" }
      expect(dana).to have_attributes(name: "Dana Whitfield", rsvp: "yes", party_size: 3, kids: 1, group: "Family",
        address: "12 Garden St\nBrooklyn, NY 11201", notes: "Can't wait!")
      expect(people.people.map { |p| [ p.name, p.rsvp ] }).to include([ "Lee Park", "no" ], [ "Sam Ortiz", "pending" ], [ "Priya Shah", "maybe" ])
    end

    it "merges rows for the same person and counts what's there" do
      people = people_from(workbook)
      expect(people.counts).to include("people" => 4, "emails" => 4, "addresses" => 1, "merged" => 1, "yes" => 1, "no" => 1, "maybe" => 1, "pending" => 1)
      expect(people.groups).to eq(%w[Work Family])
    end

    it "takes the event name from the file name when there's no title row" do
      sheet = xlsx_from([ [ "Name", "Email" ], [ "Dana", "dana@example.com" ] ])
      expect(people_from(sheet, filename: "Jonah's 5th Birthday - Guest List.xlsx").title_hint).to eq("Jonah's 5th Birthday")
    end
  end

  it "reads a legacy .xls workbook" do
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet(name: "Guests")
    sheet.row(0).concat([ "Guest Name", "E-mail Address", "RSVP" ])
    sheet.row(1).concat([ "Dana Whitfield", "dana@example.com", "Yes" ])
    io = StringIO.new
    book.write(io)

    people = people_from(io.string, filename: "guests.xls")
    expect(people.sheet.format).to eq(:xls)
    expect(people.people.sole).to have_attributes(name: "Dana Whitfield", email: "dana@example.com", rsvp: "yes")
  end

  it "reads an HTML table saved with an .xls name" do
    html = "<html><body><table><tr><th>Name</th><th>Email</th><th>Response</th></tr><tr><td>Lee Park</td><td>lee@example.com</td><td>Declined</td></tr></table></body></html>"
    expect(people_from(html, filename: "tracking.xls").people.sole).to have_attributes(name: "Lee Park", rsvp: "no")
  end

  it "reads a Google Contacts export: split names, labels, addresses, local numbers" do
    csv = <<~CSV
      First Name,Middle Name,Last Name,E-mail 1 - Type,E-mail 1 - Value,Phone 1 - Type,Phone 1 - Value,Labels,Address 1 - Street,Address 1 - City,Address 1 - Region,Address 1 - Postal Code,Address 1 - Country
      Ana,,Lima,* Home,ana@example.com,Mobile,(555) 010-0100,Book club ::: * myContacts,1 Main St,Springfield,IL,62701,USA
    CSV
    people = people_from(csv)
    expect(people.source_label).to eq("Google Contacts export")
    expect(people.people.sole).to have_attributes(name: "Ana Lima", email: "ana@example.com", phone: "+15550100100", group: "Book club",
      address: "1 Main St\nSpringfield, IL 62701\nUSA")
  end

  it "reads an Outlook export and prefers the mobile number" do
    csv = "First Name,Last Name,E-mail Address,Business Phone,Mobile Phone,Categories\nLee,Park,lee@example.com,+1 555 0100 200,+1 555 0100 300,Work\n"
    people = people_from(csv)
    expect(people.source_label).to eq("Outlook contacts export")
    expect(people.people.sole).to have_attributes(name: "Lee Park", phone: "+155501003" + "00", group: "Work")
  end

  it "reads vCards from a phone, with the address, group and mobile number" do
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      N:Whitfield;Dana;;;
      FN:Dana Whitfield
      EMAIL;type=INTERNET;type=HOME:dana@example.com
      TEL;type=HOME:+1 555 010 0999
      TEL;type=CELL:+1 555 010 0100
      ADR;type=HOME:;;12 Garden St;Brooklyn;NY;11201;USA
      CATEGORIES:Family,Neighbors
      END:VCARD
    VCF
    people = people_from(vcf, filename: "contacts.vcf")
    expect(people.source_label).to eq("Phone or iCloud contacts (vCard)")
    expect(people.people.sole).to have_attributes(name: "Dana Whitfield", phone: "+15550100100", group: "Family", address: "12 Garden St\nBrooklyn, NY 11201\nUSA")
  end

  it "reads a pasted list with no columns at all" do
    people = people_from("Dana Whitfield dana@example.com\nThe Morenos 07700 900123\n", country_code: "44")
    expect(people.people.map { |p| [ p.name, p.email, p.phone ] }).to eq([ [ "Dana Whitfield", "dana@example.com", nil ], [ "The Morenos", nil, "+447700900123" ] ])
  end

  it "guesses unlabeled columns from what's in them" do
    people = people_from("Dana Whitfield,dana@example.com,555 010 0100\nLee Park,lee@example.com,555 010 0101\n")
    expect(people.people.first).to have_attributes(name: "Dana Whitfield", email: "dana@example.com", phone: "+15550100100")
  end

  it "lets the host say what a column means" do
    csv = "Who,Contact\nDana,dana@example.com\n"
    sheet = Imports::Reader.read(csv)
    people = Imports::People.new(sheet, mapping: { "0" => "name", "1" => "email" })
    expect(people.people.sole).to have_attributes(name: "Dana", email: "dana@example.com")
  end

  describe "refusing what it shouldn't read" do
    it "rejects files over 5 MB" do
      expect { Imports::Reader.read("a" * (5.megabytes + 1)) }.to raise_error(Imports::Reader::Unreadable, /too large/)
    end

    it "rejects zip files that aren't workbooks, and workbooks that inflate suspiciously" do
      not_a_workbook = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("hello.txt"); zip.write("hi") }.string
      expect { Imports::Reader.read(not_a_workbook) }.to raise_error(Imports::Reader::Unreadable, /Excel/)

      bomb = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("xl/workbook.xml"); zip.write("<workbook/>")
        zip.put_next_entry("xl/worksheets/sheet1.xml"); zip.write("0" * (Imports::Reader::MAX_UNZIPPED_BYTES + 1))
      end.string
      expect(bomb.bytesize).to be < 1.megabyte
      expect { Imports::Reader.read(bomb) }.to raise_error(Imports::Reader::Unreadable, /too large/)
    end
  end

  describe PhoneNumber do
    it "adds the host's country code to local numbers" do
      expect(PhoneNumber.with_country("(555) 010-0100", "1")).to eq("+15550100100")
      expect(PhoneNumber.with_country("07700 900123", "44")).to eq("+447700900123")
      expect(PhoneNumber.with_country("0044 7700 900123", "1")).to eq("+447700900123")
      expect(PhoneNumber.with_country("+33 6 12 34 56 78", "1")).to eq("+33612345678")
      expect(PhoneNumber.with_country("5550100", nil)).to eq("5550100")
    end
  end
end
