require "rails_helper"

RSpec.describe "Sidekiq & Sidekiq Cron Configuration" do
  let(:dummy_worker_class) do
    Class.new do
      include Sidekiq::Job
      sidekiq_options queue: :default, retry: 3

      def perform(payload)
        payload
      end
    end
  end

  before do
    stub_const("DummyDiagnosticsWorker", dummy_worker_class)
  end

  it "enqueues jobs into the default queue in fake testing mode" do
    Sidekiq::Testing.fake! do
      expect {
        DummyDiagnosticsWorker.perform_async("ping")
      }.to change(DummyDiagnosticsWorker.jobs, :size).by(1)
    end
  end

  it "loads config/schedule.yml cleanly without syntax errors" do
    schedule_path = Rails.root.join("config/schedule.yml")
    expect(File).to exist(schedule_path)
    expect { YAML.load_file(schedule_path) }.not_to raise_error
  end
end
