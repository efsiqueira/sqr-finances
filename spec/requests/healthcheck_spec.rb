require "rails_helper"

RSpec.describe "Application Healthcheck", type: :request do
  describe "GET /up" do
    it "returns HTTP 200 OK when the application and database are healthy" do
      get rails_health_check_path
      expect(response).to have_http_status(:ok)
    end

    it "connects to PostgreSQL 16 successfully" do
      version = ActiveRecord::Base.connection.select_value("SHOW server_version;")
      expect(version).to start_with("16.")
    end
  end
end
