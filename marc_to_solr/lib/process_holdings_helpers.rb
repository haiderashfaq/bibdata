class ProcessHoldingsHelpers
  attr_reader :record

  def initialize(record:)
    @record = record
  end

  def holding_id(field_852)
    if field_852['8'] && alma?(field_852)
      holding_id = field_852['8']
    elsif field_852['0'] && scsb?(field_852)
      holding_id = field_852['0']
    end
  end

  def alma?(field_852)
    alma_code_start_22?(field_852['8'])
  end

  def scsb?(field_852)
    scsb_doc?(record['001'].value) && field_852['0']
  end

  def group_866_867_868_on_holding_perm_id(holding_perm_id, field_852)
    if scsb?(field_852)
      record.fields("866".."868").select { |f| f["0"] == holding_perm_id }
    else
      record.fields("866".."868").select { |f| f["8"] == holding_perm_id }
    end
  end

  def group_876_on_holding_perm_id(holding_id)
    record.fields("876").select { |f| f["0"] == holding_id }
  end

  # Select 852 fields from an Alma or SCSB record
  def fields_852_alma_or_scsb
    record.fields('852').select do |f|
      alma_code_start_22?(f['8']) || scsb_doc?(record['001'].value) && f['0']
    end
  end

  # Build the current location code from 876$y and 876$z
  def current_location_code(field_876)
    "#{field_876['y']}$#{field_876['z']}" if field_876['y'] && field_876['z']
  end

  # Build the permanent location code from 852$b and 852$c
  def permanent_location_code(field_852)
    "#{field_852['b']}$#{field_852['c']}"
  end

  # Select 876 fields (items) with permanent location. 876 location is equal to the 852 permanent location.
  def select_permanent_location_876(group_876_fields, field_852)
    return group_876_fields if /^scsb/.match?(field_852['b'])
    group_876_fields.select do |field_876|
      !in_temporary_location(field_876, field_852)
    end
  end

  # Select 876 fields (items) with current location. 876 location is NOT equal to the 852 permanent location.
  def select_temporary_location_876(group_876_fields, field_852)
    return [] if /^scsb/.match?(field_852['b'])
    group_876_fields.select do |field_876|
      in_temporary_location(field_876, field_852)
    end
  end

  def in_temporary_location(field_876, field_852)
    # temporary location is any item whose 876 and 852 do not match
    # for our purposes if the item is in Resource Sharing it is NOT in a temporary location so we will ignore the 876
    current_location = current_location_code(field_876)
    current_location != 'RES_SHARE$IN_RS_REQ' && current_location != permanent_location_code(field_852)
  end

  # Build the current (temporary) holding.
  def current_holding(holding_current, field_852, field_876)
    holding_current["location_code"] ||= current_location_code(field_876)
    holding_current['current_location'] ||= Traject::TranslationMap.new("locations", default: "__passthrough__")[holding_current['location_code']]
    holding_current['current_library'] ||= Traject::TranslationMap.new("location_display", default: "__passthrough__")[holding_current['location_code']]
    holding_current['call_number'] ||= []
    holding_current['call_number'] << [field_852['h'], field_852['i'], field_852['k'], field_852['j']].compact.reject(&:empty?)
    holding_current['call_number'].flatten!
    holding_current['call_number'] = holding_current['call_number'].join(' ').strip if holding_current['call_number'].present?
    holding_current['call_number_browse'] ||= []
    holding_current['call_number_browse'] << [field_852['h'], field_852['i'], field_852['k'], field_852['j']].compact.reject(&:empty?)
    holding_current['call_number_browse'].flatten!
    holding_current['call_number_browse'] = holding_current['call_number_browse'].join(' ').strip if holding_current['call_number_browse'].present?
    # Updates current holding key; values are from 852
    if field_852['l']
      holding_current['shelving_title'] ||= []
      holding_current['shelving_title'] << field_852['l']
    end
    if field_852['z']
      holding_current['location_note'] ||= []
      holding_current['location_note'] << field_852['z']
    end
    holding_current
  end

  # Build the permanent holding from 852$b$c
  def permanent_holding(holding, field_852)
    holding['location_code'] ||= field_852['b']
    # Append 852c to location code 852b if it's an Alma item
    # Do not append the 852c if it is a SCSB - we save the SCSB locations as scsbnypl and scsbcul
    holding['location_code'] += "$#{field_852['c']}" if field_852['c'] && alma?(field_852)
    holding['location'] ||= Traject::TranslationMap.new("locations", default: "__passthrough__")[holding['location_code']]
    holding['library'] ||= Traject::TranslationMap.new("location_display", default: "__passthrough__")[holding['location_code']]
    # calculate call_number for permanent location
    holding['call_number'] ||= []
    holding['call_number'] << [field_852['h'], field_852['i'], field_852['k'], field_852['j']].compact.reject(&:empty?)
    holding['call_number'].flatten!
    holding['call_number'] = holding['call_number'].join(' ').strip if holding['call_number'].present?
    holding['call_number_browse'] ||= []
    holding['call_number_browse'] << [field_852['h'], field_852['i'], field_852['k'], field_852['j']].compact.reject(&:empty?)
    holding['call_number_browse'].flatten!
    holding['call_number_browse'] = holding['call_number_browse'].join(' ').strip if holding['call_number_browse'].present?
    if field_852['l']
      holding['shelving_title'] ||= []
      holding['shelving_title'] << field_852['l']
    end
    if field_852['z']
      holding['location_note'] ||= []
      holding['location_note'] << field_852['z']
    end
    holding
  end

  # Build the items array in all_holdings hash
  def holding_items(value:, all_holdings:, item:)
    if all_holdings[value].present?
      if all_holdings[value]["items"].nil?
        all_holdings[value]["items"] = [item]
      else
        all_holdings[value]["items"] << item
      end
    end
    all_holdings
  end

  def build_item(item:, field_852:, field_876:)
    is_scsb = scsb?(field_852)
    item[:holding_id] = field_876['0'] if field_876['0']
    item[:enumeration] = field_876['3'] if field_876['3']
    item[:id] = field_876['a'] if field_876['a']
    item[:status_at_load] = field_876['j'] if field_876['j']
    item[:barcode] = field_876['p'] if field_876['p']
    item[:copy_number] = field_876['t'] if field_876['t']
    item[:use_statement] = field_876['h'] if field_876['h'] && is_scsb
    item[:storage_location] = field_876['l'] if field_876['l'] && is_scsb
    item[:cgd] = field_876['x'] if field_876['x'] && is_scsb
    item[:collection_code] = field_876['z'] if field_876['z'] && is_scsb
    item
  end

  def process_866_867_868_fields(fields:, all_holdings:, holding_id:)
    fields.each do |field|
      location_has_value = []
      supplements_value = []
      indexes_value = []
      location_has_value << field['a'] if field.tag == '866' && field['a']
      location_has_value << field['z'] if field.tag == '866' && field['z']
      supplements_value << field['a'] if field.tag == '867' && field['a']
      supplements_value << field['z'] if field.tag == '867' && field['z']
      indexes_value << field['a'] if field.tag == '868' && field['a']
      indexes_value << field['z'] if field.tag == '868' && field['z']
      next unless all_holdings[holding_id]
      all_holdings[holding_id]['location_has'] ||= []
      all_holdings[holding_id]['supplements'] ||= []
      all_holdings[holding_id]['indexes'] ||= []
      all_holdings[holding_id]['location_has'] << location_has_value.join(' ') if location_has_value.present?
      all_holdings[holding_id]['supplements'] << supplements_value.join(' ') if supplements_value.present?
      all_holdings[holding_id]['indexes'] << indexes_value.join(' ') if indexes_value.present?
    end
    all_holdings
  end
end
