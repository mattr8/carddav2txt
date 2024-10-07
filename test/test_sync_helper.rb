require 'minitest/autorun'
require 'mocha/minitest'
require 'front_matter_parser'
require_relative '../lib/sync_helper'

class TestSyncHelper < Minitest::Test
  class MockVcard
    include Mocha::API
    attr_reader :mock_object

    def initialize(opts = { name: 'John Doe', uid: 'ab12' })
      @mock_object = mock
      @mock_object.stubs(:name).returns(stub(fullname: opts[:name]))
      @mock_object.stubs(:[]).with('UID').returns(opts[:uid])
      @mock_object.stubs(:birthday).returns(stub(to_s: opts[:bday]))
      @mock_object.stubs(:note).returns(opts[:note])
      @mock_object.stubs(:telephones).returns(opts[:telephones] || [])
      @mock_object.stubs(:emails).returns(opts[:emails] || [])
      @mock_object.stubs(:addresses).returns(opts[:addresses] || [])
    end
  end

  class MockVcardField
    include Mocha::API
    attr_reader :mock_object

    def initialize(val)
      @mock_object = mock
      @mock_object.stubs(:to_s).returns(val)
    end
  end

  class MockVcardAddress
    include Mocha::API
    attr_reader :mock_object

    def initialize(opts)
      @mock_object = mock
      @mock_object.stubs(:street).returns(opts[:street])
      @mock_object.stubs(:locality).returns(opts[:locality])
      @mock_object.stubs(:region).returns(opts[:region])
      @mock_object.stubs(:postalcode).returns(opts[:postalcode])
      @mock_object.stubs(:country).returns(opts[:country])
    end
  end

  include SyncHelper

  def teardown
    folder_with_generated_files = File.join(File.dirname(__FILE__), 'fixtures/generated')
    Dir.glob("#{folder_with_generated_files}/*.md").each { |generated_file| File.delete(generated_file) }
    super
  end

  def test_validate_unique_fullnames_with_unique_vcards
    vcards = [
      MockVcard.new({ name: 'Name1' }).mock_object,
      MockVcard.new({ name: 'Name2' }).mock_object
    ]
    assert_nil(validate_unique_fullnames!(vcards))
  end

  def test_validate_unique_fullnames_with_duplicate_vcards
    vcards = [
      MockVcard.new({ name: 'Name1' }).mock_object,
      MockVcard.new({ name: 'Name1' }).mock_object,
      MockVcard.new({ name: 'Name2' }).mock_object,
      MockVcard.new({ name: 'Name2' }).mock_object
    ]

    assert_raises(RuntimeError, 'Duplicate names detected: Name1, Name2') do
      validate_unique_fullnames!(vcards)
    end
  end

  def test_build_txt_cards_hash_for_destination_folder
    destination_folder = File.join(File.dirname(__FILE__), 'fixtures/contacts')
    result = build_txt_cards_hash_for(destination_folder, '.md')
    expected_hash = {
      'ab2' => 'Arletha Johnson.md',
      'ab3' => 'Prof. Patricia Greenfelder.md',
      'ab4' => 'Rubin Kuhn.md'
    }

    assert_equal(expected_hash, result)
  end

  def test_replace_front_matter
    destination_folder = File.join(File.dirname(__FILE__), 'fixtures/generated')
    initial_front_matter = {
      'fn' => 'Matthew Robert',
      'uid' => 'ab8',
      'bday' => nil,
      'tel' => ['919-672-5877'],
      'email' => ['matthew@example.com'],
      'address' => nil,
      'notes' => nil
    }
    vcard = build_vcard_from(initial_front_matter)
    contact_file = File.join(File.dirname(__FILE__), 'fixtures', "generated/#{initial_front_matter['fn']}.md")

    write_txt_card(vcard, destination_folder, '.md')
    assert_equal(initial_front_matter, resulting_front_matter_for(contact_file))

    new_front_matter = {
      'fn' => 'Matthew Robert',
      'uid' => 'ab8',
      'bday' => nil,
      'tel' => ['206-672-5877'],
      'email' => ['matt@example.com'],
      'address' => nil,
      'notes' => nil
    }

    vcard = build_vcard_from(new_front_matter)
    contact_full_path = File.join(destination_folder, 'Matthew Robert.md')

    replace_front_matter(vcard, contact_full_path)
    assert_equal(new_front_matter, resulting_front_matter_for(contact_file))
  end

  def test_write_txt_card
    destination_folder = File.join(File.dirname(__FILE__), 'fixtures/generated')
    tel = MockVcardField.new('773-340-6525').mock_object
    email = MockVcardField.new('arletha@example.com').mock_object
    address = MockVcardAddress.new({
                                     street: "Suite 239\n12845 Ali Fords",
                                     locality: 'New Walton',
                                     region: 'MS',
                                     postalcode: '79297'
                                   }).mock_object
    vcard = MockVcard.new({
                            name: 'Arletha Johnson',
                            uid: 'ab2',
                            telephones: [tel],
                            emails: [email],
                            addresses: [address]
                          }).mock_object
    write_txt_card(vcard, destination_folder, '.md')

    expected_file_content = load_fixture('contacts/Arletha Johnson.md')
    resulting_file_content = load_fixture('generated/Arletha Johnson.md')
    assert_equal(expected_file_content, resulting_file_content)
  end

  def test_get_card_uids_to_archive_with_archivable_uids
    destination_folder = File.join(File.dirname(__FILE__), 'fixtures/contacts')
    txt_cards_hash = build_txt_cards_hash_for(destination_folder, '.md')
    vcards = [
      MockVcard.new({ name: 'Rubin Kuhn', uid: 'ab4' }).mock_object,
      MockVcard.new({ name: 'Arletha Johnson', uid: 'ab2' }).mock_object
    ]
    result = get_card_uids_to_archive(vcards, txt_cards_hash)

    assert_equal(['ab3'], result)
  end

  def test_get_card_uids_to_archive_with_no_archivable_uids
    destination_folder = File.join(File.dirname(__FILE__), 'fixtures/contacts')
    txt_cards_hash = build_txt_cards_hash_for(destination_folder, '.md')
    vcards = [
      MockVcard.new({ name: 'Rubin Kuhn', uid: 'ab4' }).mock_object,
      MockVcard.new({ name: 'Prof. Arletha Johnson', uid: 'ab3' }).mock_object,
      MockVcard.new({ name: 'Arletha Johnson', uid: 'ab2' }).mock_object
    ]
    result = get_card_uids_to_archive(vcards, txt_cards_hash)

    assert_equal([], result)
  end

  private

  def load_fixture(filename)
    File.read(File.join(File.dirname(__FILE__), 'fixtures', filename))
  end

  def build_vcard_from(front_matter)
    tel = MockVcardField.new(front_matter['tel'].first).mock_object
    email = MockVcardField.new(front_matter['email'].first).mock_object
    MockVcard.new({
                    name: front_matter['fn'],
                    uid: front_matter['uid'],
                    telephones: [tel],
                    emails: [email]
                  }).mock_object
  end

  def resulting_front_matter_for(contact_file)
    loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
    FrontMatterParser::Parser.parse_file(contact_file, loader: loader).front_matter
  end
end
