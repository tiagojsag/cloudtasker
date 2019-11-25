# frozen_string_literal: true

require 'cloudtasker/unique_job'
require 'cloudtasker/cron'
require 'cloudtasker/batch'

Cloudtasker.configure do |config|
  #
  # GCP Configuration
  #
  config.gcp_location_id = 'us-east1'
  config.gcp_project_id = 'some-project'
  config.gcp_queue_id = 'some-queue'

  #
  # Domain
  #
  # config.processor_host = 'https://xxxx.ngrok.io'
  #
  config.processor_host = 'http://localhost:3000'

  #
  # Uncomment to process tasks via Cloud Task.
  # Requires a ngrok tunnel.
  #
  # config.mode = :production
end

#
# Setup cron job
#
# Cloudtasker::Cron::Schedule.load_from_hash!(
#   'my_worker' => {
#     'worker' => 'CronWorker',
#     'cron' => '* * * * *'
#   }
# )
