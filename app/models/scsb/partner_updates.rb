require 'json'

module Scsb
  class PartnerUpdates
    def initialize(dump:, timestamp:, s3_bucket: Scsb::S3Bucket.new)
      @dump = dump
      @s3_bucket = s3_bucket
      @update_directory = ENV['SCSB_PARTNER_UPDATE_DIRECTORY'] || '/tmp/updates'
      @scsb_file_dir = ENV['SCSB_FILE_DIR']
      @last_dump = timestamp.to_time
      @inv_xml = []
      @tab_newline = []
      @leader = []
      @composed_chars = []
      @bad_utf8 = []
    end

    def process_full_files
      @dump_file_constant = 'RECAP_RECORDS_FULL'
      prepare_directory
      nypl_file = download_full_file(/NYPL.*\.zip/)
      cul_file = download_full_file(/CUL.*\.zip/)
      process_partner_updates(files: [cul_file], file_prefix: 'scsbfull_cul_')
      process_partner_updates(files: [nypl_file], file_prefix: 'scsbfull_nypl_')
      log_record_fixes
    end

    def process_incremental_files
      @dump_file_constant = 'RECAP_RECORDS'
      prepare_directory
      update_files = download_partner_updates
      process_partner_updates(files: update_files)
      log_record_fixes
      delete_files = download_partner_deletes
      process_partner_deletes(files: delete_files)
    end

    private

      def download_partner_updates
        file_list = @s3_bucket.list_files(prefix: ENV['SCSB_S3_PARTNER_UPDATES'] || 'data-exports/PUL/MARCXml/Incremental')
        @s3_bucket.download_files(files: file_list, timestamp_filter: @last_dump, output_directory: @update_directory)
      end

      def download_partner_deletes
        file_list = @s3_bucket.list_files(prefix: ENV['SCSB_S3_PARTNER_DELETES'] || 'data-exports/PUL/Json/Incremental')
        @s3_bucket.download_files(files: file_list, timestamp_filter: @last_dump, output_directory: @update_directory)
      end

      def download_full_file(file_filter)
        prefix = ENV['SCSB_S3_PARTNER_FULLS'] || 'data-exports/PUL/MARCXml/Full'
        @s3_bucket.download_recent(prefix: prefix, output_directory: @update_directory, file_filter: file_filter)
      end

      def process_partner_updates(files:, file_prefix: 'scsbupdate')
        xml_files = []
        files.each do |file|
          filename = File.basename(file, '.zip')
          filename.gsub!(/^[^_]+_([0-9]+)_([0-9]+).*$/, '\1_\2')
          file_increment = 1
          Zip::File.open(file) do |zip_file|
            zip_file.each do |entry|
              target = "#{@update_directory}/#{filename}_#{file_increment}.xml"
              xml_files << target
              entry.extract(target)
              file_increment += 1
            end
          end
          File.unlink(file)
        end
        filepaths = []
        xml_files.each do |file|
          filename = File.basename(file)
          reader = MARC::XMLReader.new(file.to_s, external_encoding: 'UTF-8')
          filepath = "#{@scsb_file_dir}/#{file_prefix}#{filename}"
          writer = MARC::XMLWriter.new(filepath)
          reader.each { |record| writer.write(process_record(record)) }
          writer.close
          filepaths << filepath
          File.unlink(file)
        end
        filepaths.sort.each { |f| attach_dump_file(f) }
      end

      def process_partner_deletes(files:)
        json_files = []
        files.each do |file|
          filename = File.basename(file, '.zip')
          file_increment = 1
          Zip::File.open(file) do |zip_file|
            zip_file.each do |entry|
              target = "#{@update_directory}/scsbdelete#{filename}_#{file_increment}.json"
              json_files << target
              entry.extract(target)
              file_increment += 1
            end
          end
          File.unlink(file)
        end
        ids = []
        json_files.each do |file|
          scsb_ids(file, ids)
          File.unlink(file)
        end
        @dump.delete_ids = ids
        @dump.save
      end

      def scsb_ids(filename, ids)
        file = File.read(filename)
        data = JSON.parse(file)
        data.each do |record|
          ids << "SCSB-#{record['bib']['bibId']}"
        end
        ids
      end

      def process_record(record)
        record = field_delete(['856', '959'], record)
        if bad_utf8?(record)
          @bad_utf8 << record['001']
          record = bad_utf8_fix(record)
        end
        if invalid_xml_chars?(record)
          @inv_xml << record['001']
          record = invalid_xml_fix(record)
        end
        if tab_newline_char?(record)
          @tab_newline << record['001']
          record = tab_newline_fix(record)
        end
        if leader_errors?(record)
          @leader << record['001']
          record = leaderfix(record)
        end
        if composed_chars_errors?(record)
          @composed_chars << record['001']
          record = composed_chars_normalize(record)
        end
        record = extra_space_fix(record)
        empty_subfield_fix(record)
      end

      def attach_dump_file(filepath, constant = nil)
        constant ||= @dump_file_constant
        dump_file_type = DumpFileType.find_by(constant: constant)
        df = DumpFile.create(dump_file_type: dump_file_type, path: filepath)
        df.zip
        df.save
        @dump.dump_files << df
        @dump.save
      end

      def log_record_fixes
        log_file = {
          inv_xml: @inv_xml,
          tab_newline: @tab_newline,
          leader: @leader,
          composed_chars: @composed_chars,
          bad_utf8: @bad_utf8
        }
        filepath = log_file_name
        File.write(filepath, log_file.to_json.to_s)
        attach_dump_file(filepath, 'LOG_FILE')
      end

      def log_file_name
        "#{@scsb_file_dir}/fixes_#{@last_dump.strftime('%Y_%m_%d')}.json"
      end

      def prepare_directory
        FileUtils.mkdir_p(@update_directory)
      end
  end
end
