class BlueButtonParser
  
  attr_reader :text, :data, :config

  ALWAYS_SKIP_LINES = ["^[-]+$", "^[-]+[ ]+$", "^[ ]+[-]+", "^[=]+$", "^(- ){5,}", "END OF MY HEALTHEVET"]

  DEFAULT_CONFIG = {
    "MY HEALTHEVET PERSONAL INFORMATION REPORT" => {
      :same_line_keys => ["Name", "Date of Birth"],
    },
    "DOWNLOAD REQUEST SUMMARY" => {},
    "MY HEALTHEVET ACCOUNT SUMMARY" => {
      :collection => {"Facilities" => {:table_columns => ["VA Treating Facility", " Type"]}}
    },
    "DEMOGRAPHICS" => {
      :collection => {"EMERGENCY CONTACTS" => {:item_starts_with => "Contact First Name"}},      
      :same_line_keys => [["Gender", "Blood Type", "Organ Donor"], ["Work Phone Number", "Extension"]],
    },    
    "HEALTH CARE PROVIDERS" => {
      :collection => {"Providers" => {:item_starts_with => "Provider Name"}},
      :same_line_keys => ["Phone Number", "Ext"],
    },
    "TREATMENT FACILITIES" => {
      :collection => {"Facilities" => {:item_starts_with => "Facility Name"}},
      :same_line_keys => [["Facility Type", "VA Home Facility"], ["Phone Number", "Ext"]],      
    },
    "HEALTH INSURANCE" => {
      :collection => {"Companies" => {:item_starts_with => "Health Insurance Company"}},
      :same_line_keys => [["ID Number", "Group Number"], ["Start Date", "Stop Date"]],
    },
    "VA WELLNESS REMINDERS" => {
      :collection => {"Reminders" => {:table_columns => ["Wellness Reminder", "Due Date", "Last Completed", "Location"]}}
    },
    "VA APPOINTMENTS" => {
      :collection => {"Appointments" => {:item_starts_with => "Date/Time"}},
      :skip_lines => ["^FUTURE APPOINTMENTS:", "^PAST APPOINTMENTS:"]
    },
    "VA MEDICATION HISTORY" => {
      :collection => {"Medications" => {:item_starts_with => "Medication"}},
    },
    "MEDICATIONS AND SUPPLEMENTS" => {
      :collection => {"Medications" => {:item_starts_with => "Category"}},
      :same_line_keys => [["Start Date", "Stop Date"], ["Pharmacy Name", "Pharmacy Phone"]],
    },
    "VA ALLERGIES" => {
      :collection => {"Allergies" => {:item_starts_with => "Allergy Name"}},
    },
    "ALLERGIES/ADVERSE REACTIONS" => {
      :collection => {"Allergies" => {:item_starts_with => "Allergy Name"}},
    },
    "MEDICAL EVENTS" => {
      :collection => {"Event" => {:item_starts_with => "Medical Event"}},      
    },
    "IMMUNIZATIONS" => {
      :collection => {"Immunizations" => {:item_starts_with => "Immunization"}},
    },
    "VA LABORATORY RESULTS" => {
      :collection => {"Labs" => {:item_starts_with => "Lab Test"}},
    },
    "LABS AND TESTS" => {
      :collection => {"Labs" => {:item_starts_with => "Test Name"}},
    },
    "VITALS AND READINGS" => {
      :collection => {"Reading" => {:item_starts_with => "Measurement Type"}},      
    },
    "FAMILY HEALTH HISTORY" => {
      :collection => {"Relation" => {:item_starts_with => "Relationship"}},            
    },
    "MILITARY HEALTH HISTORY" => {
      :same_line_keys => [["Service Branch", "Rank"],["Location of Service", "Onboard Ship"]]
    },    
    "DOD MILITARY SERVICE INFORMATION" => {
      :collection => {
        "Regular Active Service" => {:table_starts_with => "-- Regular Active Service", :table_columns => ["Service", "Begin Date", "End Date", "Character of Service", "Rank"] },
        "Reserve/Guard Association Periods" => {:table_starts_with => "-- Reserve/Guard Association Periods", :table_columns => ["Service", "Begin Date", "End Date", "Character of Service", "Rank"] },
        "DoD MOS/Occupation Codes" => {:table_starts_with => "-- Note: Both Service and DoD Generic codes", :table_columns => ["Service", "Begin Date", "Enl/Off", "Type", "Svc Occ Code", "DoD Occ Code"]}
      },
      :skip_lines => ["^Translations of Codes Used in this Section"]
    }
  }
  
  def initialize(bb_data_text, config=DEFAULT_CONFIG, newline="\n")
    @text = bb_data_text
    @config= config
    @data = parse_text(@text, newline)
  end
  
  private
  
  def new_section?(line)
    new_section = line.match(/^[-]+ (.*) [-]+/) 
    new_section = new_section[1] if new_section     
    return new_section
  end
  
  def new_collection?(line, last_line, current_section)
    new_collection = nil

    if collections = sect_config(current_section, :collection)
      collections.each_pair do |name, collection_config|  
        if starts_with = collection_config[:item_starts_with]
          if line.match(Regexp.new("^#{starts_with}:"))
            new_collection = name
            break
          end
        elsif table_columns = collection_config[:table_columns]
          new_table = false
          
          if table_starts_with = collection_config[:table_starts_with]
            if last_line.match(Regexp.new("^#{table_starts_with}"))
              new_table = true
            end
          else
            new_table = true
          end
      
          if new_table
            regexp_str = ".?#{table_columns.join('.*')}.?"
            if line.match(Regexp.new(regexp_str))
              new_collection = name
              break
            end
          end
          
        end
      end
    end
    
    return new_collection
  end
    
  def get_multi_key_values(line, current_section)
    key_values = nil

    if key_sets = sect_config(current_section, :same_line_keys)
      unless key_sets.first.is_a?(Array)
        key_sets = [key_sets]
      end
      
      key_sets.each do |keys|
        regexp_str = keys.collect{|k| "#{k}: (.*)"}.join
        regexp = Regexp.new(regexp_str)
        if keys_match = line.match(regexp)
          key_values = Hash.new
          keys.each_with_index do |key, index|
            key_values[key] = keys_match[index + 1]
          end
          break
        end
      end
    end
    
    return key_values
  end
    
  def get_single_key_value(line)    
    if key_match = line.match(/(.*)\: (.*)?/) 
      key_values = {key_match[1] => key_match[2]}
    elsif key_match = line.match(/(.*):$/)
      key_values = {key_match[1] => nil}
    else
      key_values = nil      
    end

    return key_values
  end  
  
  def get_key_values(line, current_section)
    key_values = get_multi_key_values(line, current_section) 
    key_values = get_single_key_value(line) if key_values.nil?            
    return key_values
  end
  
  def key_ended?(line)
    # either an empty line or a line starting with a key (e.g. "Status:") means we're done with multi-line
    line.empty? or line.match(/^\S(.*): (\S*)/)
  end
  
  def sect_config(current_section, key)
    if @config[current_section]
      @config[current_section][key]
    else
      nil
    end
  end  
  
  def parse_table_line(line, columns, column_widths)
    row = Hash.new
    columns.each_with_index do |column, index|
      start = column_widths[index]
      finish = if index == column_widths.size - 1
          line.size
        else
          column_widths[index + 1]
        end
      val_str = (line[start, finish-start]).strip
      val_str = val_str.empty? ? nil : val_str
      row[column] = val_str
    end
    return row
  end
  
  def table_columns(current_section, current_collection)
    sect_config(current_section, :collection)[current_collection][:table_columns]
  end
  
  def column_widths(line, columns)
    columns.collect{|c| line.index(c)}
  end
  
  def parse_text(text, newline="\n")    
    # parse text line by line
    lines = text.split(newline)

    # state variables
    current_section = nil    
    current_collection = nil
    current_key = nil
    current_table = nil
    
    # put parsed data into this hash
    data = Hash.new    
    
    # start parsing
    lines.each_with_index do |line, index|
      skip_regexps = (ALWAYS_SKIP_LINES + (sect_config(current_section, :skip_lines) || [])).compact
      skip_regexps = skip_regexps.collect{|r| Regexp.new(r)}
      next if skip_regexps.find{|re| re.match(line)}
      
      if collection = new_collection?(line, lines[index - 1], current_section)
        current_collection = collection
        current_key = nil
        data[current_section][current_collection] ||= []
        if columns = table_columns(current_section, current_collection)
          current_table = {:columns => columns, :widths => column_widths(line, columns)}
          next
        else
          data[current_section][current_collection] << Hash.new
        end
      end

      if key_ended?(line)
        current_key = nil
      end

      if current_section and current_key
        value = line.rstrip
        if current_collection.nil?
          data[current_section][current_key] = [data[current_section][current_key], value].compact.join(" \n")
        else
          (data[current_section][current_collection].last)[current_key] = [(data[current_section][current_collection].last)[current_key], value].compact.join(" \n")
        end
      end
      
      if section = new_section?(line)
        current_section = section        
        current_collection = nil
        data[current_section] ||= {}
      elsif current_table
        if line.empty?
          current_collection = nil
          current_table = nil
        else
          data[current_section][current_collection] << parse_table_line(line, current_table[:columns], current_table[:widths])
        end
      elsif (!current_key and current_section and key_values = get_key_values(line, current_section))
        key_values.each_pair do |key, value|
          val = (value.nil? or value.strip.empty?) ? nil : value.strip #empty strings should be converted to nils
          if current_collection.nil?
            data[current_section][key] = val
          else
            (data[current_section][current_collection].last)[key] = val
          end
          current_key = key
        end
      end
    end

    return data
  end

end