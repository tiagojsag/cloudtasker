# frozen_string_literal: true

RSpec.describe Cloudtasker::Task do
  let(:config) { Cloudtasker.config }
  let(:client) { instance_double('Google::Cloud::Tasks::V2beta3::CloudTasksClient') }
  let(:worker) { TestWorker.new(job_args: job_args, job_meta: job_meta) }
  let(:job_args) { ['foo', 1] }
  let(:job_meta) { { foo: 'bar' } }
  let(:job_id) { nil }
  let(:task) { described_class.new(worker) }

  describe '.find' do
    subject { described_class.find(id) }

    let(:id) { '222' }
    let(:client) { instance_double('Google::Cloud::V2beta3::Tasks') }

    before { allow(described_class).to receive(:client).and_return(client) }

    context 'with task found' do
      let(:resp) { instance_double('Google::Cloud::Tasks::V2beta3::Task') }

      before { allow(described_class.client).to receive(:get_task).with(id).and_return(resp) }
      it { is_expected.to eq(resp) }
    end

    context 'with task not found' do
      before do
        allow(described_class.client).to receive(:get_task)
          .with(id)
          .and_raise(Google::Gax::RetryError.new('msg'))
      end
      it { is_expected.to be_nil }
    end
  end

  describe '.delete' do
    subject { described_class.delete(id) }

    let(:id) { '222' }
    let(:client) { instance_double('Google::Cloud::V2beta3::Tasks') }

    before { allow(described_class).to receive(:client).and_return(client) }

    context 'with task found' do
      let(:resp) { instance_double('Google::Cloud::Tasks::V2beta3::Task') }

      before { allow(described_class.client).to receive(:delete_task).with(id).and_return(resp) }
      it { is_expected.to eq(resp) }
    end

    context 'with task not found' do
      before do
        allow(described_class.client).to receive(:delete_task)
          .with(id)
          .and_raise(Google::Gax::RetryError.new('msg'))
      end
      it { is_expected.to be_nil }
    end
  end

  describe '.new' do
    subject { task }

    it { is_expected.to have_attributes(worker: worker) }
  end

  describe '.client' do
    subject { described_class.client }

    before { allow(Google::Cloud::Tasks).to receive(:new).with(version: :v2beta3).and_return(client) }

    it { is_expected.to eq(client) }
  end

  describe '.worker_from_payload' do
    subject { described_class.worker_from_payload(payload) }

    let(:id) { SecureRandom.uuid }
    let(:worker_class) { TestWorker }
    let(:worker_class_name) { worker_class.to_s }
    let(:payload) do
      {
        'worker' => worker_class_name,
        'job_id' => id,
        'job_args' => job_args,
        'job_meta' => job_meta
      }
    end

    context 'with valid worker' do
      it { is_expected.to be_a(worker_class) }
      it { is_expected.to have_attributes(job_args: job_args, job_id: id, job_meta: eq(job_meta)) }
    end

    context 'with worker class not implementing Cloudtasker::Worker' do
      let(:worker_class) { TestNonWorker }

      it { is_expected.to be_nil }
    end

    context 'with invalid worker class' do
      let(:worker_class_name) { 'ClassThatDoesNotExist' }

      it { is_expected.to be_nil }
    end
  end

  describe '.execute_from_payload!' do
    subject(:execute) { described_class.execute_from_payload!(payload) }

    let(:payload) { { 'foo' => 'bar' } }

    before { allow(described_class).to receive(:worker_from_payload).with(payload).and_return(worker) }

    context 'with valid worker' do
      let(:worker) { instance_double('TestWorker') }
      let(:ret) { 'some-result' }

      before { allow(worker).to receive(:execute).and_return(ret) }
      it { is_expected.to eq(ret) }
    end

    context 'with invalid worker' do
      let(:worker) { nil }

      it { expect { execute }.to raise_error(Cloudtasker::InvalidWorkerError) }
    end
  end

  describe '#client' do
    subject { task.client }

    before { allow(described_class).to receive(:client).and_return(client) }

    it { is_expected.to eq(client) }
  end

  describe '#config' do
    subject { task.config }

    it { is_expected.to eq(Cloudtasker.config) }
  end

  describe '#queue_path' do
    subject { task.queue_path }

    let(:queue_path) { 'my/queue' }

    before do
      allow(described_class).to receive(:client).and_return(client)
      allow(client).to receive(:queue_path).with(
        config.gcp_project_id,
        config.gcp_location_id,
        config.gcp_queue_id
      ).and_return(queue_path)
    end

    it { is_expected.to eq(queue_path) }
  end

  describe '#task_payload' do
    subject { task.task_payload }

    let(:expected_payload) do
      {
        http_request: {
          http_method: 'POST',
          url: config.processor_url,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{Cloudtasker::Authenticator.verification_token}"
          },
          body: task.worker_payload.to_json
        }
      }
    end

    around { |e| Timecop.freeze { e.run } }
    it { is_expected.to eq(expected_payload) }
  end

  describe '#worker_payload' do
    subject { task.worker_payload }

    let(:expected_payload) do
      {
        worker: worker.class.to_s,
        job_id: worker.job_id,
        job_args: job_args,
        job_meta: job_meta
      }
    end

    it { is_expected.to eq(expected_payload) }
  end

  describe '#schedule_time' do
    subject { task.schedule_time(interval: interval, time_at: time_at) }

    let(:interval) { nil }
    let(:time_at) { nil }

    context 'with no args' do
      it { is_expected.to be_nil }
    end

    context 'with interval' do
      let(:interval) { 10 }
      let(:expected_time) do
        ts = Google::Protobuf::Timestamp.new
        ts.seconds = Time.now.to_i + interval.to_i
        ts
      end

      around { |e| Timecop.freeze { e.run } }
      it { is_expected.to eq(expected_time) }
    end

    context 'with time_at' do
      let(:time_at) { Time.now }
      let(:expected_time) do
        ts = Google::Protobuf::Timestamp.new
        ts.seconds = time_at.to_i
        ts
      end

      it { is_expected.to eq(expected_time) }
    end

    context 'with time_at and interval' do
      let(:time_at) { Time.now }
      let(:interval) { 50 }
      let(:expected_time) do
        ts = Google::Protobuf::Timestamp.new
        ts.seconds = time_at.to_i + interval
        ts
      end

      it { is_expected.to eq(expected_time) }
    end
  end

  describe '#schedule' do
    subject { task.schedule(**attrs) }

    let(:attrs) { {} }
    let(:queue_path) { 'some-queue' }
    let(:expected_payload) { task.task_payload }
    let(:resp) { instance_double('Class: Google::Cloud::Tasks::V2beta3::Task') }

    around { |e| Timecop.freeze { e.run } }
    before { allow(task).to receive(:queue_path).and_return(queue_path) }
    before { allow(task).to receive(:client).and_return(client) }
    before { allow(client).to receive(:create_task).with(queue_path, expected_payload).and_return(resp) }

    context 'with no delay' do
      it { is_expected.to eq(resp) }
    end

    context 'with scheduled time' do
      let(:attrs) { { interval: 10, time_at: Time.now } }
      let(:expected_payload) { task.task_payload.merge(schedule_time: task.schedule_time(attrs)) }

      it { is_expected.to eq(resp) }
    end
  end
end
