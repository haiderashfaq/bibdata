# This service is intended to be run by a daemon. It watches the AWS SQS poll
# for full dump events and kicks off a job to process them.
class AwsSqsPoller
  def self.poll
    queue_url = Rails.configuration.alma["sqs_queue_url"]
    poller = Aws::SQS::QueuePoller.new(queue_url)

    poller.poll do |msg|
      message_body = JSON.parse(msg[:body])
      job_name = message_body["job_instance"]["name"]
      next unless jobs_map.keys.include?(job_name)
      dump = AlmaDumpFactory.bib_dump(
        message_body,
        jobs_map[job_name]
      )
      # running dump creation in the background prevents the queue
      # event from timing out and requeuing
      AlmaDumpTransferJob.perform_later(
        dump: dump,
        job_id: message_body["job_instance"]["id"]
      )
    end
  end
end

def jobs_map
  @jobs_map ||= Rails.configuration.alma[:job_name_record_type]
end

class AlmaDumpFactory
  attr_reader :message
  def initialize(message)
    @message = message
  end

  def self.bib_dump(message, constant)
    new(message).bib_dump(constant)
  end

  def bib_dump(constant)
    dump = Dump.create(dump_type: DumpType.find_by(constant: constant))
    dump.event = dump_event
    dump.save
    dump
  end

  def dump_event
    @event ||= Event.create(
      start: event_start,
      finish: event_finish,
      success: true,
      message_body: message.to_json
    )
  end

  def event_start
    message["job_instance"]["start_time"]
  end

  def event_finish
    message["job_instance"]["end_time"]
  end
end
