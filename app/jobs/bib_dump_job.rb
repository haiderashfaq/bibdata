class BibDumpJob < ActiveJob::Base
  queue_as :default

  def perform(id_slice, df_id)
    # TODO: Re-enable. Disabled as we no longer have VoyagerHelpers.
    # df = DumpFile.find(df_id)
    # File.truncate(df.path, 0) if File.exist?(df.path)
    # VoyagerHelpers::Liberator.dump_bibs_to_file(id_slice, df.path)
    # df.zip
    # df.save
  end
end
