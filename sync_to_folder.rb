#!/usr/bin/env ruby

require 'fileutils'
require 'vcard'
# require "pry-byebug"
require_relative 'lib/sync_helper'

include SyncHelper

extension = ENV['CARDDAV2TXT_FILE_EXTENSION'] || '.txt'
destination_folder = ENV['CARDDAV2TXT_DESTINATION_PATH'] || raise('CARDDAV2TXT_DESTINATION_PATH must be set as an environment variable')
cardav_user = ENV['CARDDAV_USER'] || raise('CARDDAV_USER must be set as an environment variable')
carddav_pw = ENV['CARDDAV_PW'] || raise('CARDDAV_PW must be set as an environment variable')
dav_uri = ENV['CARDDAV_URI'] || raise('CARDDAV_URI must be set as an environment variable')

raise('Destination folder must exist') unless Dir.exist?(destination_folder)

all_vcard_data = fetch_vcard_data(dav_uri, cardav_user, carddav_pw)
vcards = Vcard::Vcard.decode(all_vcard_data)

validate_unique_fullnames!(vcards)

txt_cards_hash = build_txt_cards_hash_for(destination_folder, extension)

archived_path = File.join(destination_folder, 'archived')
FileUtils.mkdir_p(archived_path)

cards_uids_to_archive = get_card_uids_to_archive(vcards, txt_cards_hash)
cards_uids_to_archive.each do |card_uid|
  contact_file = File.join(destination_folder, txt_cards_hash[card_uid])
  FileUtils.mv(contact_file, archived_path)
  puts "Contact: #{txt_cards_hash[card_uid]} archived"
end

fullname_changes = {}
vcards.each do |card|
  contact_filename = txt_cards_hash[card["UID"]]

  # If found, sync the contact in-place. If the filename differs, don't rename the file, but record the conflict.
  # The filename conflicts will be outputted to the user upon exit.
  if contact_filename
    contact_file_basename = File.basename(contact_filename, extension)
    contact_full_path = File.join(destination_folder, contact_filename)
    fullname_changes[contact_file_basename] = card.name.fullname if card.name.fullname != contact_file_basename

    replace_front_matter(card, contact_full_path)
  else
    write_txt_card(card, destination_folder, extension)
  end
end

fullname_changes.each do |from, to|
  puts "Contact changed from: #{from}, to: #{to}"
  puts 'Please take care to change the filename and any references to the file.'
end

puts "All done!"
