require 'helper'

class BlueButtonParserTest < Test::Unit::TestCase
  
  def test_parse_section_breaks
    str = <<-EOS
----------------------------- SECTION 1 ----------------------------
foo
------------------------- SECTION 2 -------------------------
Instructions: -- TAKE WITH FOOD --

---------------------------------
EOS
    bbp = BlueButtonParser.new(str)
    assert_equal ["SECTION 1", "SECTION 2"], bbp.data.keys, "parser should correctly construct sections in hash output"
  end
  
  def test_parse_simple_key_value
    str = <<-EOS
------- SECTION ---------
Zip/Post Code: 00001
EOS
    expected = {"SECTION" => {"Zip/Post Code" => "00001"}}
    bbp = BlueButtonParser.new(str)
    assert_equal(expected, bbp.data, "should handle simple case with one key-value pair")
  end

  def test_parse_multiple_key_values
    str = <<-EOS
------- SECTION ---------
Name: MHVTESTVETERAN, ONE                       Date of Birth: 01 Mar 1948
EOS
    expected = {"SECTION" => {"Name" => "MHVTESTVETERAN, ONE", "Date of Birth" => "01 Mar 1948"}}
    config = {"SECTION" => {:same_line_keys => ["Name", "Date of Birth"]}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should handle two key-value pairs in single line")
  end
      
  def test_parse_two_sets_of_multiple_key_values_in_same_section
    str = <<-EOS
------- SECTION ---------
Name: MHVTESTVETERAN, ONE                       Date of Birth: 01 Mar 1948
Gender: Male   Blood Type: AB+         Organ Donor: Yes
EOS
    expected = {"SECTION" => {"Name" => "MHVTESTVETERAN, ONE", "Date of Birth" => "01 Mar 1948", "Gender" => "Male", "Blood Type" => "AB+", "Organ Donor" => "Yes"}}
    config = {"SECTION" => {:same_line_keys => [["Name", "Date of Birth"], ["Gender", "Blood Type", "Organ Donor"]]}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should handle a section having two sets of key-value pairs in single lines")
  end

  def test_parse_line_wrap_value_with_empty_line_delimiter
    str = <<-EOS
------ SECTION ---------
Comments: BP taken standing.  BP continues at goal.  Doctor says to continue BP 
medications as directed

EOS
    expected = {"SECTION" => {"Comments" => "BP taken standing.  BP continues at goal.  Doctor says to continue BP \nmedications as directed"}}
    bbp = BlueButtonParser.new(str)
    assert_equal(expected, bbp.data, "should handle value that wraps lines")
  end        
  
  def test_parse_line_wrap_value_without_empty_line_delimiter
    str = <<-EOS
------ SECTION ---------
Results: BP taken standing.  BP continues at goal.  Doctor says to continue BP 
medications as directed
Status: pending
EOS
    expected = {"SECTION" => {"Results" => "BP taken standing.  BP continues at goal.  Doctor says to continue BP \nmedications as directed", "Status" => "pending"}}
    bbp = BlueButtonParser.new(str)
    assert_equal(expected, bbp.data, "should handle value that wraps lines but does not end with empty line")
  end
  
  def test_parse_line_wrap_value_with_dashed_line
    # As seen in IMMUNIZATIONS/Reactions
    str = <<-EOS
------ SECTION ---------
Reactions:
---------------------------------
Pain

EOS
    expected = {"SECTION" => {"Reactions" => "Pain"}}
    bbp = BlueButtonParser.new(str)
    assert_equal(expected, bbp.data, "should handle value that wraps lines")
  end
    
  def test_parse_line_wrap_value_with_keyish_item_in_value
    str = <<-EOS
------ SECTION ---------
Note:           This appointment has pre-appointment activity scheduled:
                Lab:    27 Jan 2012 @ 1000

EOS
    expected = {"SECTION" => {"Note" => "This appointment has pre-appointment activity scheduled: \n                Lab:    27 Jan 2012 @ 1000"}}
    bbp = BlueButtonParser.new(str)
    assert_equal(expected, bbp.data, "should handle value that wraps lines, but has a key-like element in the wrapped text")
  end
  
  def test_parse_collections_with_empty_line_delimiter
    str = <<-EOS
------ SECTION ---------
Contact Name: Foo
Contact Email: Zip

Contact Name: Bar
Contact Email: Zap

EOS
    expected = {"SECTION" => {"Contacts" => [
        {"Contact Name" => "Foo", "Contact Email" => "Zip"}, 
        {"Contact Name" => "Bar", "Contact Email" => "Zap"}] }}
    config = {"SECTION" => {:collection => {"Contacts" => {:item_starts_with => "Contact Name"}}}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should find collections")    
  end  
  
  def test_parse_collections_with_empty_line_not_a_delimiter
    # As seen in the "MEDICATIONS AND SUPPLEMENTS" section
    str = <<-EOS
------ SECTION ---------
Contact Name: Foo
Contact Email: Zip

Contact Location: MA

Contact Name: Bar
Contact Email: Zap

Contact Location: CA

EOS
    expected = {"SECTION" => {"Contacts" => [
        {"Contact Name" => "Foo", "Contact Email" => "Zip", "Contact Location" => "MA"}, 
        {"Contact Name" => "Bar", "Contact Email" => "Zap", "Contact Location" => "CA"}] }}
    config = {"SECTION" => {:collection => {"Contacts" => {:item_starts_with => "Contact Name"}}}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should find collections where you can't assume empty line is a delimiter")    
  end  
  
  def test_columns_widths
    bbp = BlueButtonParser.new("")
    line = "  Foo Bar Sup"
    columns = ["Foo", "Bar", "Sup"]
    expected_widths = [2, 6, 10]
    assert_equal expected_widths, bbp.send(:column_widths, line, columns)
  end
  
  def test_parse_table_line
    bbp = BlueButtonParser.new("")
    line = "  a   b   c  "
    columns = ["Foo", "Bar", "Sup"]    
    widths = [2, 6, 10]
    expected_output = {"Foo" => "a", "Bar" => "b", "Sup" => "c"}
    assert_equal expected_output, bbp.send(:parse_table_line, line, columns, widths)    
  end
  
  def test_parse_tables
    # Note that "Type" column header does not start at same character position as the row values!
    str = <<-EOS
--------------------- SECTION ---------------------

    VA Treating Facility                     Type
    ----------------------------            -----------  
    AUSTIN MHV                              OTHER
    PORTLAND, OREGON VA MEDICAL CENTER      VAMC

EOS
    expected = {"SECTION" => {"Facilities" => [
      {"VA Treating Facility" => "AUSTIN MHV", " Type" => "OTHER"}, 
      {"VA Treating Facility" => "PORTLAND, OREGON VA MEDICAL CENTER", " Type" => "VAMC"}] }}
    config = {"SECTION" => {:collection => {"Facilities" => {:table_columns => ["VA Treating Facility", " Type"]}}}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should parse simple table")    
  end
  
  def test_parse_tables_with_missing_values  
    str = <<-EOS
---------------------------- SECTION -------------------------

Wellness Reminder                  Due Date    Last Completed   Location
----------------------------------------------------------------------------
Control of Your Cholesterol        DUE NOW     UNKNOWN          PORTLAND, OR
Pneumonia Vaccine                              06 Mar 2011      PORTLAND, OR

EOS
    expected = {"SECTION" => {"Reminders" => [
      {"Wellness Reminder" => "Control of Your Cholesterol", "Due Date" => "DUE NOW", "Last Completed" => "UNKNOWN", "Location" => "PORTLAND, OR"}, 
      {"Wellness Reminder" => "Pneumonia Vaccine", "Due Date" => nil, "Last Completed" => "06 Mar 2011", "Location" => "PORTLAND, OR"}
    ]}}
    config = {"SECTION" => {:collection => {"Reminders" => {:table_columns => ["Wellness Reminder", "Due Date", "Last Completed", "Location"]}}}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data, "should parse simple table with missing value")    
  end

  def test_parse_multiple_tables_with_same_columns
    str = <<-EOS
---------------------------- SECTION -------------------------

-- Regular Active Service
Service      Begin Date  End Date    Character of Service   Rank
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Army         06/11/2005  03/26/2007  Honorable              COL

-- Reserve/Guard Association Periods
Service      Begin Date  End Date    Character of Service   Rank
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Army Guard   01/11/1987  08/24/1993  Unknown                

EOS
    expected = {"SECTION" => {
      "Regular Active Service"=> [{"Service" => "Army", "Begin Date" => "06/11/2005", "End Date" => "03/26/2007", "Character of Service" => "Honorable", "Rank" => "COL"}],
      "Reserve/Guard Association Periods"=>  [{"Service" => "Army Guard", "Begin Date" => "01/11/1987", "End Date" => "08/24/1993", "Character of Service" => "Unknown", "Rank" => nil}]
    }}
    config = {"SECTION" => {:collection => {
      "Regular Active Service" => {:table_starts_with => "-- Regular Active Service", :table_columns => ["Service", "Begin Date", "End Date", "Character of Service", "Rank"] },
      "Reserve/Guard Association Periods" => {:table_starts_with => "-- Reserve/Guard Association Periods", :table_columns => ["Service", "Begin Date", "End Date", "Character of Service", "Rank"] },
    }}}
    bbp = BlueButtonParser.new(str, config)
    assert_equal(expected, bbp.data)    
  end      
        
  def test_parse_entire_sample_blue_button_document
    bbp = BlueButtonParser.new(File.read(File.dirname(__FILE__) + "/data/blue_button_example_data.txt"))
    parsed_data = bbp.data
    expected_data = JSON.parse(File.read(File.dirname(__FILE__) + "/data/expected_json_output.js"))
    
    sections = [
      "MY HEALTHEVET PERSONAL INFORMATION REPORT",
      "DOWNLOAD REQUEST SUMMARY",
      "MY HEALTHEVET ACCOUNT SUMMARY",
      "DEMOGRAPHICS",
      "HEALTH CARE PROVIDERS",
      "TREATMENT FACILITIES",
      "HEALTH INSURANCE",
      "VA WELLNESS REMINDERS",
      "VA APPOINTMENTS",
      "VA MEDICATION HISTORY",
      "MEDICATIONS AND SUPPLEMENTS",
      "VA ALLERGIES",
      "ALLERGIES/ADVERSE REACTIONS",
      "MEDICAL EVENTS",
      "IMMUNIZATIONS",
      "VA LABORATORY RESULTS",
      "LABS AND TESTS",
      "VITALS AND READINGS",
      "FAMILY HEALTH HISTORY",
      "MILITARY HEALTH HISTORY",
    ]
                        
    sections.each do |section|
      assert_equal expected_data[section], parsed_data[section], "parsed section does not match expected JSON for section '#{section}'"            
    end
  end
    
end