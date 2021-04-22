require 'rails_helper'

RSpec.describe LocationDataService, type: :service do
  subject(:service) { described_class.new }

  before do
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/libraries.json")
      )

    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries/arch/locations")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/locations1.json")
      )

    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries/annex/locations")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/locations2.json")
      )
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries/online/locations")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/locations3.json")
      )
  end

  describe "#delete_existing_and_repopulate" do
    before do
      # Setup fake records to test if existing records are deleted
      test_library = Locations::Library.create(code: 'test', label: 'test')
      Locations::HoldingLocation.new(code: 'test', label: 'test') do |test_location|
        test_location.library = test_library
        test_location.save
      end
      Locations::DeliveryLocation.new(label: 'test', address: 'test') do |test_delivery_location|
        test_delivery_location.library = test_library
        test_delivery_location.save
      end
    end

    it "deletes existing data and populates library and location data from Alma excluding elfs" do
      LocationDataService.delete_existing_and_repopulate
      library_record = Locations::Library.find_by(code: 'arch')
      location_record1 = Locations::HoldingLocation.find_by(code: 'arch$stacks')
      location_record2 = Locations::HoldingLocation.find_by(code: 'annex$stacks')
      location_record3 = Locations::HoldingLocation.find_by(code: 'online$elf1')
      location_record4 = Locations::HoldingLocation.find_by(code: 'online$elf2')
      location_record5 = Locations::HoldingLocation.find_by(code: 'online$elf3')
      location_record6 = Locations::HoldingLocation.find_by(code: 'online$elf4')
      location_record7 = Locations::HoldingLocation.find_by(code: 'online$cdl')

      expect(Locations::Library.count).to eq 3
      expect(Locations::HoldingLocation.count).to eq 31
      expect(library_record.label).to eq 'Architecture Library'
      expect(location_record2.label).to eq 'Annex Stacks'
      expect(location_record1.open).to be true
      expect(location_record2.open).to be false
      expect(location_record3).to be nil
      expect(location_record4).to be nil
      expect(location_record5).to be nil
      expect(location_record6).to be nil
      expect(location_record7.code).to eq 'online$cdl'
    end

    it "deletes existing delivery locations table and populates new from json file" do
      LocationDataService.delete_existing_and_repopulate
      library_record = Locations::Library.find_by(code: 'annex')
    end
  end
end
