class LocationDataService
  # Delete existing locations data repopulate tables with data from Alma
  def self.delete_existing_and_repopulate
    new.delete_existing_and_repopulate
  end

  def delete_existing_and_repopulate
    DeliveryLocation.delete_all
    HoldingLocation.delete_all
    Library.delete_all
    populate_libraries
    populate_delivery_locations
    populate_holding_locations
  end

  def populate_libraries
    libraries.each do |library|
      Library.create(
        label: library.name,
        code: library.code
      )
    end
  end

  # Iterates through Alma Libraries
  # Finds voyager holding location with flag values from holding_locations_array based on the mapped holding_location_code
  # Iterates through Alma holding_locations based on the Alma library code and
  def populate_holding_locations
    libraries.each do |library|
      library_record = Library.find_by(code: library.code)
      # Use the holding_locations file to update the flags based on the holding_location_code
      holding_locations(library.code).each do |holding_location|
        next if ["elf1", "elf2", "elf3", "elf4"].include? holding_location.code
        holding_location_record = holding_locations_array.find { |v| v["holding_location_code"] == "#{library.code}$#{holding_location.code}" }
        HoldingLocation.new do |location_record|
          location_record.label = holding_location.external_name
          location_record.code = "#{library.code}$#{holding_location.code}"
          location_record.remote_storage = holding_location.remote_storage
          if holding_location_record.present?
            location_record.aeon_location = holding_location_record['aeon_location']
            location_record.recap_electronic_delivery_location = holding_location_record['recap_electronic_delivery_location']
            location_record.requestable = holding_location_record['requestable']
            location_record.always_requestable = holding_location_record['always_requestable']
            location_record.circulates = holding_location_record['circulates']
            location_record.open = holding_location_record['open']
            location_record.holding_library_id = holding_library_id(holding_location_record["holding_library"]["code"]) if holding_location_record.present? && holding_location_record["holding_library"].present?
          end
          location_record.library = library_record
          location_record.save
        end
      end
    end
    update_holding_library
    populate_partners_holding_locations
    set_holding_delivery_locations
  end

  # Populate delivery locations based on the delivery_locations.json
  # @note Do NOT remove values from here without updating Figgy appropriately.
  # The URIs are referenced in Figgy and removing them will break manifests.
  # These values will not change when we move to alma.
  def populate_delivery_locations
    highest_id = delivery_locations_array.sort_by { |x| x["id"] }.last["id"]
    # Reset the auto-increment column so it starts above the highest count.
    DeliveryLocation.connection.execute("ALTER SEQUENCE locations_delivery_locations_id_seq RESTART WITH #{highest_id + 1}")
    delivery_locations_array.each do |delivery_location|
      library_record = find_library_by_code(delivery_location["alma_library_code"])
      DeliveryLocation.new do |delivery_record|
        delivery_record.id = delivery_location['id']
        delivery_record.label = delivery_location['label']
        delivery_record.address = delivery_location['address']
        delivery_record.phone_number = delivery_location['phone_number']
        delivery_record.contact_email = delivery_location['contact_email']
        delivery_record.staff_only =  delivery_location['staff_only']
        delivery_record.library = library_record
        delivery_record.gfa_pickup = delivery_location['gfa_pickup']
        delivery_record.pickup_location = delivery_location['pickup_location']
        delivery_record.digital_location = delivery_location['digital_location']
        delivery_record.save
      end
    end
  end

  def populate_partners_holding_locations
    partners_locations = [
      { label: "", code: "scsbcul", aeon_location: false, recap_electronic_delivery_location: true, open: false, requestable: true, always_requestable: false, circulates: true, remote_storage: 'recap_rmt' },
      { label: "", code: "scsbnypl", aeon_location: false, recap_electronic_delivery_location: true, open: false, requestable: true, always_requestable: false, circulates: true, remote_storage: 'recap_rmt' },
      { label: "", code: "scsbhl", aeon_location: false, recap_electronic_delivery_location: true, open: false, requestable: true, always_requestable: false, circulates: true, remote_storage: 'recap_rmt' }
    ]
    partners_locations.each do |p|
      HoldingLocation.new do |location_record|
        location_record.label = p[:label]
        location_record.code = p[:code]
        location_record.aeon_location = p[:aeon_location]
        location_record.recap_electronic_delivery_location = p[:recap_electronic_delivery_location]
        location_record.open = p[:open]
        location_record.requestable = p[:requestable]
        location_record.always_requestable = p[:always_requestable]
        location_record.circulates = p[:circulates]
        location_record.library = Library.find_by(code: "recap")
        location_record.remote_storage = p[:remote_storage]
        location_record.save
        # QX is the delivery location for scsb
        location_record.delivery_location_ids = delivery_library_ids(["QX"])
      end
    end
  end

  # Update joined table for holding and delivery locations
  # based on the holding_locations file and the mapped holding_location_code value
  def set_holding_delivery_locations
    HoldingLocation.all.each do |location_record|
      holding_location_record = holding_locations_array.find { |v| v["holding_location_code"] == location_record.code }
      location_record.delivery_location_ids = delivery_library_ids(holding_location_record["delivery_locations"]) if holding_location_record.present? && holding_location_record["delivery_locations"].present?
    end
  end

  private

    # Updates holding library for two old recap locations rccpt, rccpw
    # These locations did not have a holding library.
    # It is set here so that there is no need for customization in the generated holding_locations.json file, every time it needs to be generated.
    def update_holding_library
      new_recap_holding_location_codes = ["arch$pw", "engineer$pt"]
      new_recap_holding_location_codes.each do |location_record_code|
        holding_location_record = HoldingLocation.find_by(code: location_record_code)
        holding_location_record.holding_library_id = holding_library_id(location_record_code[0...-3])
        holding_location_record.save
      end
    end

    def holding_library_id(holding_library_code)
      library = find_library_by_code(holding_library_code)
      library.id if library.present?
    end

    # Find the delivery library using the gfa_pickup value
    # example: gfa_pickup = ["QT", "QA", "PA", "QC"] for anxbnc
    def delivery_library_ids(gfa_pickup)
      ids = []
      gfa_pickup.each do |d|
        delivery_location = DeliveryLocation.all.find { |m| m["gfa_pickup"] == d }
        ids << delivery_location.id if delivery_location.present?
      end
      ids
    end

    # Find the library using the library code
    def find_library_by_code(code)
      Library.find_by(code: code)
    end

    # Parses voyager_locations.json file
    # Creates an array of holding_location hashes
    def holding_locations_array
      file_to_service = LocationsToFileService.new
      file_to_service.holding_locations_array
    end

    # Parses delivery_locations.json file
    # Creates an array of delivery_location hashes
    def delivery_locations_array
      file_to_service = LocationsToFileService.new
      file_to_service.delivery_locations_array
    end

    # Retrieves holding locations from Alma.
    # @param library_code [String] e.g. "main"
    # @return Alma::LocationSet
    def holding_locations(library_code)
      Alma::Location.all(library_code: library_code)
    end

    # Retrieves libraries from Alma.
    # @return Alma::LibrarySet
    def libraries
      @libraries ||= Alma::Library.all
    end
end