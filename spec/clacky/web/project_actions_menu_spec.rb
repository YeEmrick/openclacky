# frozen_string_literal: true

RSpec.describe "Project actions menu UI" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:projects) { File.read(File.join(web_dir, "projects.js")) }
  let(:sessions) { File.read(File.join(web_dir, "sessions.js")) }
  let(:styles) { File.read(File.join(web_dir, "app.css")) }

  it "embeds Lucide Pencil, Brush, and Trash icons for the three actions" do
    expect(projects).to include(
      'addItem(isPinned ? "projects.menu.unpin" : "projects.menu.pin",'
    )
    expect(projects).to include(
      'isPinned ? "Unpin" : "Pin to top", iconPin, false, pinToggle);'
    )
    expect(projects).to include(
      'addItem("projects.menu.edit", "Edit Project", iconEdit, false'
    )
    expect(projects).to include(
      'addItem("projects.menu.deleteSessions", "Delete Sessions", iconClearSessions, false'
    )
    expect(projects).to include(
      'addItem("projects.menu.delete", "Delete", iconTrash, true'
    )
    expect(projects).to include('viewBox="0 0 24 24" width="14" height="14"')
    expect(projects).to include('stroke="currentColor" stroke-width="2"')
    expect(projects).to include(
      'M12 20h9'
    )
    expect(projects).to include('M3 6h18')
    expect(projects).to include('const iconEdit = `<svg')
    expect(projects).to include('const iconPin = `<svg')
    expect(projects).to include('const iconClearSessions = `<svg')
    expect(projects).to include('const iconTrash = `<svg')
  end

  it "sorts pinned projects first and renders a pin badge" do
    expect(projects).to include("const pa = a.pinned_at || \"\"")
    expect(projects).to include("if (pa !== pb) return pb.localeCompare(pa)")
    expect(projects).to include("if (project.pinned_at)")
    expect(projects).to include('pin.className = "project-pin-badge"')
  end

  it "matches the existing 14px menu icon size and themes only deletion as dangerous" do
    expect(styles).to match(
      /\.project-actions-menu-icon \{.*?width: 0\.875rem;.*?height: 0\.875rem;/m
    )
    expect(styles).not_to include("project-edit.svg")
    expect(styles).not_to include("project-trash.svg")
    expect(styles).to include(".project-actions-menu-icon svg")
  end

  it "keeps the delete entry neutral until hovered, like the session menu" do
    expect(styles).not_to include(".project-actions-menu-item.danger::before")
    expect(styles).not_to match(/\.project-actions-menu-item\.danger \{.*?margin-top/m)

    icon = styles[/^\.project-actions-menu-item\.danger \.project-actions-menu-icon \{.*?\n\}/m]
    expect(icon).to include("var(--color-text-secondary)")

    hover = styles[/^\.project-actions-menu-item\.danger:hover \{.*?\n\}/m]
    expect(hover).to include("var(--color-error-bg)")
    expect(hover).to include("color: var(--color-error)")

    hover_icon = styles[/^\.project-actions-menu-item\.danger:hover \.project-actions-menu-icon \{.*?\n\}/m]
    expect(hover_icon).to include("var(--color-error)")
  end

  it "reuses the session menu trash glyph for deletion" do
    session_icon = sessions[/const iconTrash = `([^`]+)`/, 1]
    project_icon = projects[/const iconTrash = `([^`]+)`/, 1]
    expect(session_icon).not_to be_nil
    expect(project_icon).to eq(session_icon)
  end

  describe "archive all sessions" do
    let(:i18n) { File.read(File.join(web_dir, "i18n.js")) }

    it "sits right above Delete, behind the same divider the session menu uses" do
      clear_at    = projects.index('addItem("projects.menu.deleteSessions"')
      divider_at  = projects.index('divider.className = "project-actions-menu-divider"')
      archive_at  = projects.index('addItem("projects.menu.archiveSessions"')
      delete_at   = projects.index('addItem("projects.menu.delete"')

      expect([clear_at, divider_at, archive_at, delete_at]).to all(be_a(Integer))
      expect(divider_at).to be > clear_at
      expect(archive_at).to be > divider_at
      expect(delete_at).to be > archive_at

      expect(projects).to include("const iconArchive = `<svg")
      expect(projects).to include("iconArchive, false, () => promptArchiveSessions")
      expect(styles).to match(
        /\.project-actions-menu-divider \{.*?height: 1px;.*?background: var\(--color-border-secondary\);/m
      )
    end

    it "archives through the project-scoped endpoint, not one call per session" do
      expect(projects).to include("`/api/projects/${id}/sessions/archive`")
      expect(projects).to include('method: "POST" }')
      expect(projects).not_to match(%r{\/api/sessions\/\$\{.*\}.{0,80}archived: true}m)
    end

    it "always asks for confirmation before archiving" do
      confirm_at = projects.index("await Modal.confirm(\n      I18n.t(\"projects.archiveSessions.confirm\"")
      fetch_at   = projects.index("`/api/projects/${id}/sessions/archive`")

      expect(confirm_at).not_to be_nil, "archive must open the confirm dialog"
      expect(fetch_at).to be > confirm_at, "the POST must come after the confirmation"

      # The dialog must not be gated on the sidebar copy of the session list:
      # cron/ext sessions live in folded groups and would make it look empty.
      body = projects[confirm_at...fetch_at]
      expect(body).to include("if (!confirmed) return;")
      expect(body).not_to include("ids.length === 0")
    end

    it "confirms with the project name" do
      expect(projects).to include("projects.archiveSessions.confirm")
      expect(projects).to include("{ name: project.name }")
      expect(projects).to include('Modal.toast(I18n.t("projects.archiveSessions.empty"), "info")')
    end

    it "reports the server-side archive count" do
      expect(projects).to include("if (!data.archived)")
      expect(projects).to include('I18n.t("projects.archiveSessions.done", { count: data.archived })')
    end

    it "localizes the label, the confirmation and the result in both languages" do
      expect(i18n).to include('"projects.menu.archiveSessions": "Archive Sessions"')
      expect(i18n).to include('"projects.menu.archiveSessions": "归档会话"')
      expect(i18n).to include('Archive all sessions in project \\"{{name}}\\"?')
      expect(i18n).to include('"projects.archiveSessions.done": "已归档 {{count}} 个会话"')
      expect(i18n).to include('"projects.archiveSessions.fail": "Archive failed: {{msg}}"')
    end
  end
end
