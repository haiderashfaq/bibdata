class AlmaAdapter
  class AlmaItem < SimpleDelegator
    attr_reader :item
    # @param item [Alma::BibItem]
    def initialize(item)
      @item = item
      super(item)
    end

    def composite_location
      "#{library}$#{location}"
    end

    def composite_temp_location
      return unless in_temp_location?
      "#{temp_library}$#{temp_location}"
    end

    def composite_perm_location
      "#{holding_library}$#{holding_location}"
    end

    # @note This is called type because item_type is the value used in the
    #   /items endpoint. In migrating to Alma this is largely the policy value
    #   with a fallback.
    def type
      return "Gen" unless item_data["policy"]["value"].present?
      item_data["policy"]["value"]
    end

    # 876 field used for enrichment in
    # AlmaAdapter::MarcRecord#enrich_with_item
    def enrichment_876
      MARC::DataField.new(
        '876', '0', '0',
        *subfields_for_876
      )
    end

    def subfields_for_876
      [
        MARC::Subfield.new('0', holding_id),
        MARC::Subfield.new('3', enum_cron),
        MARC::Subfield.new('a', item_id),
        MARC::Subfield.new('p', barcode),
        MARC::Subfield.new('t', copy_number)
      ] + recap_876_fields
    end

    def recap_876_fields
      return [] unless item.library == "recap"
      [
        MARC::Subfield.new('h', recap_use_restriction),
        MARC::Subfield.new('x', group_designation),
        MARC::Subfield.new('z', recap_customer_code),
        MARC::Subfield.new('j', recap_status),
        MARC::Subfield.new('l', "RECAP"),
        MARC::Subfield.new('k', item.holding_library)
      ]
    end

    # Status isn't used for recap records, but 876j is a required field.
    def recap_status
      "Not Used"
    end

    def enum_cron
      return if enumeration.blank? && chronology.blank?
      return enumeration if chronology.blank?
      return chronology if enumeration.blank?
      "#{enumeration} (#{chronology})"
    end

    def enumeration
      enums = []
      enums << item.item_data["enumeration_a"]
      enums << item.item_data["enumeration_b"]
      enums << item.item_data["enumeration_c"]
      enums << item.item_data["enumeration_d"]
      enums << item.item_data["enumeration_e"]
      enums << item.item_data["enumeration_f"]
      enums << item.item_data["enumeration_g"]
      enums << item.item_data["enumeration_h"]
      enums.reject(&:blank?).join(", ")
    end

    def chronology
      chrons = []
      chrons << item.item_data["chronology_i"]
      chrons << item.item_data["chronology_j"]
      chrons << item.item_data["chronology_k"]
      chrons << item.item_data["chronology_l"]
      chrons << item.item_data["chronology_m"]
      chrons.reject(&:blank?).join(", ")
    end

    def holding_id
      item.holding_data["holding_id"]
    end

    def item_id
      item.item_data["pid"]
    end

    def barcode
      item.item_data["barcode"]
    end

    def copy_number
      item.holding_data["copy_id"]
    end

    def call_number
      item.holding_data["call_number"]
    end

    def cdl?
      item.item_data.dig("work_order_type", "value") == "CDL"
    end

    def recap_customer_code
      return unless item.library == "recap"
      return "PG" if item.location[0].casecmp("x").zero?
      item.location.upcase
    end

    def recap_use_restriction
      return unless item.library == "recap"
      case item.location
      when *in_library_recap_groups
        "In Library Use"
      when *supervised_recap_groups
        "Supervised Use"
      end
    end

    def group_designation
      return unless item.library == "recap"
      case item.location
      when 'pa', 'gp', 'qk', 'pf'
        "Shared"
      when *(in_library_recap_groups + supervised_recap_groups + no_access_recap_groups)
        "Private"
      end
    end

    def in_library_recap_groups
      ['pj', 'pk', 'pl', 'pm', 'pn', 'pt']
    end

    def supervised_recap_groups
      ["pb", "ph", "ps", "pw", "pz", "xc", "xg", "xm", "xn", "xp", "xr", "xw", "xx"]
    end

    def no_access_recap_groups
      ['jq', 'pe', 'pg', 'ph', 'pq', 'qb', 'ql', 'qv', 'qx']
    end

    # Returns a JSON representation used for the /items endpoint.
    def as_json
      item["item_data"].merge(
        "id" => item_id,
        "copy_number" => copy_number.to_i,
        "temp_location" => composite_temp_location,
        "perm_location" => composite_perm_location,
        "item_type" => type,
        "cdl" => cdl?
      )
    end

    def availability_summary(marc_holding:)
      status = calculate_status()

      {
        barcode: item_data["barcode"],
        id: item_data["pid"],
        copy_number: holding_data["copy_id"],
        status: status[:code],        # Available or ?? "Not Charged"
        status_label: status[:label], # available
        on_reserve: "N",
        item_type: item_type, # e.g., Gen
        pickup_location_id: holding_location, # stacks
        pickup_location_code: holding_location, # stacks
        location: composite_location, # firestone$stacks
        label: holding_library_name, # Firestore Library
        description: item_data["description"], # "v. 537, no. 7618 (2016 Sept. 1)" - new in Alma
        enum_display: enumeration, # in Alma there are many enumerations
        chron_display: chronology # in Alma there are many chronologies
      }.merge(temp_library_availability_summary)
    end

    def temp_library_availability_summary
      if in_temp_location?
        {
          in_temp_library: true,
          temp_library_code: temp_library,
          temp_library_label: temp_library_name,
          temp_location_code: composite_temp_location,
          temp_location_label: temp_library_name
        }
      else
        { in_temp_library: false }
      end
    end

    def item_type
      item_data.dig("policy", "value")
    end

    def status_label(marc_holding)
      value = marc_holding["availability"]
      if value.nil?
        # TODO: This will need to be figure out later on.
        #
        #   It possible that we will never hit this case because Request might not need to
        #   find out the availability for holding that meets this criteria but if it does
        #   then the current code will handle it.
        #
        #   The issue here is that the holding information that comes for these records
        #   does not have a holding for the holding_id that we are working with. Instead it has
        #   a single holding that does NOT have an ID. This seems to be an issue only for
        #   eresources.
        #
        #   For an example see: http://localhost:3000/bibliographic/9919392043506421/holdings/22105104420006421/availability.json
        #
        #   For now use the data in the item.
        value = item_data["base_status"]["desc"]
      end
      value
    end

    def calculate_status
      status = {}
      if has_work_order_type?
        status = status_from_work_order_type()
        status[:case] = "work_order"
      elsif has_process_type?
        status = status_from_process_type()
        status[:case] = "process_type"
      else
        status = status_from_base_status()
        status[:case] = "base_status"
      end
      puts "== status =="
      puts status
      puts "============"
      status
    end

    def has_work_order_type?
      !item_data.dig("work_order_type", "value").blank?
    end

    def has_process_type?
      !item_data.dig("process_type", "value").blank?
    end

    def has_base_status?
      !item_data.dig("base_status", "value").blank?
    end

    def status_from_work_order_type
      value = item_data["work_order_type"]["value"]
      desc = item_data["work_order_type"]["desc"]
      # TODO: Implement this logic
      # Source: https://developers.exlibrisgroup.com/alma/apis/docs/xsd/rest_item.xsd/
      return {code: "Available", status: desc}
    end

    def status_from_process_type
      value = item_data.dig("process_type", "value")
      desc = item_data.dig("process_type", "desc")

      # Source for values: https://developers.exlibrisgroup.com/alma/apis/docs/xsd/rest_item.xsd/
      case
      # when value == "ACQ"
      # when value == "CLAIM_RETURNED_LOAN"
      # when value == "HOLDSHELF"
      # when value == "ILL"
      when value == "LOAN"
        return {code: "Not Available", label: "On Loan"}
      when value == "LOST_ILL" || value == "LOST_LOAN" || value == "LOST_LOAN_AND_PAID"
        return {code: "Not Available", label: desc}
      when value == "MISSING"
        return {code: "Not Available", label: desc}
      # when value == "REQUESTED"
      # when value == "TECHNICAL"
      when value == "TRANSIT" || value == "TRANSIT_TO_REMOTE_STORAGE"
        return {code: "Available", label: desc}
      end

      # default to available OK?
      {code: "Available", label: "Available"}
    end

    def status_from_base_status
      value = item_data.dig("base_status", "value")
      desc = item_data.dig("base_status", "desc")

      # Source for values: https://developers.exlibrisgroup.com/alma/apis/docs/xsd/rest_item.xsd/
      if value == "1"
        return {code: "Available", label: desc}
      end

      # default to not available OK?
      {code: "Not Available", label: desc}
    end
  end
end
