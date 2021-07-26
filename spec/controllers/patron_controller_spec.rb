require 'rails_helper'

RSpec.describe PatronController, type: :controller do
  context "with an authorized ip" do
    let(:allowed_ip) { '192.168.0.1' }

    before do
      controller.request.remote_addr = allowed_ip
      allow(Rails.application.config).to receive(:ip_allowlist).and_return([allowed_ip])
    end

    it "can access patron info" do
      stub_patron
      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(200)
    end
  end

  context "with an unuathorized ip" do
    it "does not allow users that are not signed in to access patron info" do
      stub_patron
      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(403)
    end

    it "allows authenticated users to access patron info" do
      stub_patron
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(200)
    end
  end

  describe "patron_info endpoint" do
    it "allows authenticated users to access patron info" do
      stub_patron('cmonster')
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      get :patron_info, params: { patron_id: 'cmonster', format: :json }
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq(
        "netid" => "cmonster",
        "first_name" => "Cookie",
        "last_name" => "Monster",
        "barcode" => "00000000000000",
        "university_id" => "100000000",
        "patron_id" => "100000000",
        "patron_group" => "UGRD",
        "patron_group_desc" => "UGRD Undergraduate",
        "campus_authorized" => false,
        "campus_authorized_category" => "none",
        "requests_total" => 0,
        "loans_total" => 0,
        "fees_total" => 0.0,
        "active_email" => "cmonster@SCRUBBED_Princeton.EDU"
      )
    end

    it "converts patron group to 'staff'" do
      stub_patron
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)["patron_group"]).to eq "staff"
    end

    it "allows authenticated users to access patron info and ldap data when desired" do
      stub_patron
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      expect(Ldap).to receive(:find_by_netid).with('bbird').and_return(ldap_data: "is here")
      get :patron_info, params: { patron_id: 'bbird', ldap: true, format: :json }
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq(
        "netid" => "bbird",
        "first_name" => "Big",
        "last_name" => "Bird",
        "barcode" => "00000000000000",
        "university_id" => "100000000",
        "patron_id" => "100000000",
        "patron_group" => "staff",
        "patron_group_desc" => "P Faculty & Professional",
        "campus_authorized" => false,
        "campus_authorized_category" => "none",
        "requests_total" => 0,
        "loans_total" => 0,
        "fees_total" => 0.0,
        "ldap" => { "ldap_data" => "is here" },
        "active_email" => "bbird@SCRUBBED_princeton.edu"
      )
    end

    it "allows authenticated users to access just patron info when desired" do
      stub_patron
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      expect(Ldap).not_to receive(:find_by_netid)
      get :patron_info, params: { patron_id: 'bbird', ldap: 'other', format: :json }
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq(
        "netid" => "bbird",
        "first_name" => "Big",
        "last_name" => "Bird",
        "barcode" => "00000000000000",
        "university_id" => "100000000",
        "patron_id" => "100000000",
        "patron_group" => "staff",
        "patron_group_desc" => "P Faculty & Professional",
        "campus_authorized" => false,
        "campus_authorized_category" => "none",
        "requests_total" => 0,
        "loans_total" => 0,
        "fees_total" => 0.0,
        "active_email" => "bbird@SCRUBBED_princeton.edu"
      )
    end

    it "allows authenticated users to access patron info and includes campus access" do
      CampusAccess.create(uid: 'bbird')
      stub_patron
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq(
        "netid" => "bbird",
        "first_name" => "Big",
        "last_name" => "Bird",
        "barcode" => "00000000000000",
        "university_id" => "100000000",
        "patron_id" => "100000000",
        "patron_group" => "staff",
        "patron_group_desc" => "P Faculty & Professional",
        "campus_authorized" => true,
        "campus_authorized_category" => "full",
        "requests_total" => 0,
        "loans_total" => 0,
        "fees_total" => 0.0,
        "active_email" => "bbird@SCRUBBED_princeton.edu"
      )
    end

    it "retuns 404 when patron info is not found" do
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }
      netid = "ogrouch"
      stub_patron(netid, 400)
      get :patron_info, params: { patron_id: netid, format: :json }
      expect(response).to have_http_status(404)
    end
  end

  context "When Alma returns PER_THRESHOLD errors" do
    it "returns HTTP 429" do
      stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/users/bbird?expand=fees,requests,loans")
        .to_return(status: 429,
                   headers: { "Content-Type" => "application/json" },
                   body: stub_alma_per_second_threshold)
      user = double('user')
      allow(request.env['warden']).to receive(:authenticate!) { user }
      allow(controller).to receive(:current_user) { user }

      get :patron_info, params: { patron_id: 'bbird', format: :json }
      expect(response).to have_http_status(429)
    end
  end
end

def stub_patron(netid = "bbird", status = 200)
  alma_path = Pathname.new(file_fixture_path).join("alma", "patrons")
  stub_request(:get, /.*\.exlibrisgroup\.com\/almaws\/v1\/users\/#{netid}/)
    .to_return(status: status,
               headers: { "Content-Type" => "application/json" },
               body: alma_path.join("#{netid}.json"))
end
