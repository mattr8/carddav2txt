require 'front_matter_parser'
require 'net/http'
require 'nokogiri'
require 'set'
require 'uri'
require 'yaml'
require 'pry-byebug'

module SyncHelper
  def validate_unique_fullnames!(vcards)
    duplicate_names = []
    names_set = Set.new
    vcards.each do |card|
      fn = card.name.fullname
      if names_set.include?(fn)
        duplicate_names << fn
      else
        names_set.add(fn)
      end
    end

    raise("Duplicate names detected: #{duplicate_names.uniq.join(', ')}") unless duplicate_names.empty?
  end

  def build_txt_cards_hash_for(destination_folder, extension)
    txt_cards_hash = {}

    Dir.glob("#{destination_folder}/*#{extension}").each do |contact_file|
      loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
      front_matter = FrontMatterParser::Parser.parse_file(contact_file, loader: loader).front_matter
      basename = File.basename(contact_file)

      # front matter uses lowercase uid key
      txt_cards_hash[front_matter['uid']] = basename
    end

    txt_cards_hash
  end

  def replace_front_matter(vcard, contact_full_path)
    new_front_matter = YAML.dump(front_matter_for(vcard)).chomp
    file_content = File.read(contact_full_path)
    new_content = file_content.sub(/\A---\n.*\n---/m, "#{new_front_matter}\n---")
    File.write(contact_full_path, new_content)
  end

  def write_txt_card(vcard, destination_folder, extension)
    front_matter = front_matter_for(vcard)
    File.open("#{destination_folder}/#{front_matter['fn']}#{extension}", 'w') do |file|
      file.puts front_matter.to_yaml
      file.puts '---'
    end
  end

  # Cards existing in text file but missing in CardDav should be archived
  def get_card_uids_to_archive(vcards, txt_cards_hash)
    existing_card_uids = []
    vcards.each do |card|
      existing_card_uids << card['UID'] if txt_cards_hash[card['UID']]
    end

    txt_cards_hash.keys - existing_card_uids
  end

  def fetch_vcard_data(dav_uri, cardav_user, carddav_pw)
    uri = URI(dav_uri)
    req = Net::HTTP::Propfind.new(uri)
    req.basic_auth(cardav_user, carddav_pw)
    req['Depth'] = '1'
    xml_payload = <<~XML
      <?xml version="1.0" encoding="utf-8" ?>
      <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
        <d:prop>
          <card:address-data />
        </d:prop>
      </d:propfind>
    XML

    req.body = xml_payload
    res = Net::HTTP.start(uri.hostname, use_ssl: true) do |http|
      http.request(req)
    end

    doc = Nokogiri::XML(res.body)
    doc.remove_namespaces!
    doc.xpath('//prop/address-data').text.strip
  end

  private

  def build_address(vcard_address)
    base_address = [
      vcard_address.street.sub("\n", ', '),
      vcard_address.locality,
    ].compact.join(', ')

    region_and_zip = "#{vcard_address.region} #{vcard_address.postalcode}".strip

    [
      base_address,
      region_and_zip,
      vcard_address.country
    ].compact.join(', ')
  end

  def front_matter_for(vcard)
    {
      'fn' => vcard.name.fullname,
      'uid' => vcard['UID'],
      'bday' => vcard.birthday.to_s,
      'tel' => vcard.telephones.map(&:to_s),
      'email' => vcard.emails.map(&:to_s),
      'address' => vcard.addresses.map { |a| build_address(a) },
      'notes' => vcard.note
    }.transform_values { |v| v.respond_to?(:empty?) && v.empty? ? nil : v }
  end
end
