require "rails_helper"

# Carried over from the original sample app's PagesController spec.
RSpec.describe "Pages", type: :request do
  %w[root about contact].each do |page|
    it "GET #{page} is successful" do
      get page == "root" ? root_path : "/#{page}"
      expect(response).to have_http_status(:ok)
    end
  end

  it "titles pages per page" do
    get "/about"
    expect(page_text).to include("<title>About · Cordially</title>")
  end
end
