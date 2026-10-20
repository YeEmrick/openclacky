# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require "clacky/server/http_server"
require "clacky/agent_config"
require_relative "../../support/http_server_spec_helpers"

RSpec.describe Clacky::Server::HttpServer, "POST /api/projects/:id/sessions/archive" do
  include HttpServerSpecHelpers

  let(:tmproot)      { Dir.mktmpdir("clacky_project_archive_spec") }
  let(:sessions_dir) { File.join(tmproot, "sessions") }

  let(:agent_config) do
    cfg = Clacky::AgentConfig.new(models: [
      {
        "model"            => "test-model",
        "api_key"          => "sk-testkey1234567890abcd",
        "base_url"         => "https://api.example.com",
        "anthropic_format" => true,
        "type"             => "default"
      }
    ])
    stub_const("Clacky::AgentConfig::CONFIG_FILE", File.join(tmproot, "config.yml"))
    cfg
  end

  before { FileUtils.mkdir_p(sessions_dir) }
  after  { FileUtils.rm_rf(tmproot) }

  def create_project(server, name:)
    server.instance_variable_get(:@project_manager).create(name: name)
  end

  def create_session(server, name:, project_id:)
    res = fake_res
    dispatch(server, fake_req(method: "POST", path: "/api/sessions",
                              body: { name: name, project_id: project_id }), res)
    expect(res.status).to eq(201), res.body
    parsed_body(res)["session"]["id"]
  end

  def archive_project(server, project_id)
    res = fake_res
    dispatch(server, fake_req(method: "POST",
                              path: "/api/projects/#{project_id}/sessions/archive"), res)
    [res.status, parsed_body(res)]
  end

  def list_ids(server, query_string: "limit=50")
    res = fake_res
    dispatch(server, fake_req(method: "GET", path: "/api/sessions", query_string: query_string), res)
    parsed_body(res)["sessions"].map { |s| s["id"] }
  end

  # Session files written straight to disk never enter the registry, so this
  # covers the "nothing to restore" branch of the bulk archive.
  def write_disk_session(id:, name:, project_id:, archived_at: nil)
    created_at = "2026-01-01T00:00:00+00:00"
    data = {
      session_id:    id,
      name:          name,
      created_at:    created_at,
      updated_at:    created_at,
      working_dir:   tmproot,
      source:        "manual",
      agent_profile: "general",
      project_id:    project_id,
      messages:      [],
      stats:         { total_tasks: 0, total_cost_usd: 0.0 }
    }
    data[:archived_at] = archived_at if archived_at
    stamp = Time.parse(created_at).strftime("%Y-%m-%d-%H-%M-%S")
    File.write(File.join(sessions_dir, "#{stamp}-#{id[0..7]}.json"), JSON.pretty_generate(data))
  end

  it "archives every session in the project and leaves other projects alone" do
    with_server(agent_config: agent_config, sessions_dir: sessions_dir) do |server|
      target = create_project(server, name: "target")
      other  = create_project(server, name: "other")

      a = create_session(server, name: "a", project_id: target[:id])
      b = create_session(server, name: "b", project_id: target[:id])
      c = create_session(server, name: "c", project_id: other[:id])

      status, body = archive_project(server, target[:id])

      expect(status).to eq(200), body.inspect
      expect(body["archived"]).to eq(2)

      expect(list_ids(server)).not_to include(a, b)
      expect(list_ids(server)).to include(c)
      expect(list_ids(server, query_string: "archived=1&limit=50")).to contain_exactly(a, b)
    end
  end

  it "skips sessions that are already archived" do
    with_server(agent_config: agent_config, sessions_dir: sessions_dir) do |server|
      project = create_project(server, name: "mixed")
      already = create_session(server, name: "already", project_id: project[:id])
      create_session(server, name: "fresh", project_id: project[:id])

      dispatch(server, fake_req(method: "PATCH", path: "/api/sessions/#{already}",
                                body: { archived: true }), fake_res)
      first_stamp = JSON.parse(
        File.read(Dir.glob(File.join(sessions_dir, "*.json")).find { |f|
          JSON.parse(File.read(f))["session_id"] == already
        }), symbolize_names: true
      )[:archived_at]

      status, body = archive_project(server, project[:id])

      expect(status).to eq(200)
      expect(body["archived"]).to eq(1)

      kept = Dir.glob(File.join(sessions_dir, "*.json")).map { |f| JSON.parse(File.read(f)) }
                .find { |row| row["session_id"] == already }
      expect(kept["archived_at"]).to eq(first_stamp)
    end
  end

  it "stamps sessions that only exist on disk" do
    with_server(agent_config: agent_config, sessions_dir: sessions_dir) do |server|
      project = create_project(server, name: "disk")
      write_disk_session(id: "diskonly12345678", name: "disk-only", project_id: project[:id])

      status, body = archive_project(server, project[:id])

      expect(status).to eq(200)
      expect(body["archived"]).to eq(1)

      row = JSON.parse(File.read(Dir.glob(File.join(sessions_dir, "*diskonly*.json")).first))
      expect(row["archived_at"]).not_to be_nil
      expect(list_ids(server)).not_to include("diskonly12345678")
    end
  end

  it "returns 404 for an unknown project" do
    with_server(agent_config: agent_config, sessions_dir: sessions_dir) do |server|
      status, body = archive_project(server, "no-such-project")
      expect(status).to eq(404)
      expect(body["error"]).to eq("Project not found")
    end
  end

  it "reports zero when the project has nothing to archive" do
    with_server(agent_config: agent_config, sessions_dir: sessions_dir) do |server|
      project = create_project(server, name: "empty")
      status, body = archive_project(server, project[:id])
      expect(status).to eq(200)
      expect(body["archived"]).to eq(0)
    end
  end
end
