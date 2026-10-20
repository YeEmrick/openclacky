# frozen_string_literal: true

RSpec.describe "Brand status hint" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:markup)  { File.read(File.join(web_dir, "index.html")) }
  let(:script)  { File.read(File.join(web_dir, "settings.js")) }
  let(:i18n)    { File.read(File.join(web_dir, "i18n.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }

  it "places the hint inline next to the status badge" do
    card = markup[/<div id="brand-status-card".*?brand-support-contact/m]
    expect(card).not_to be_nil

    state = card[/<span class="brand-status-state">.*?<\/span>\s*<\/span>/m]
    expect(state).not_to be_nil
    expect(state).to include('id="brand-status-badge"')
    expect(state).to include('<span class="brand-status-hint" id="brand-status-hint" style="display:none"></span>')
    expect(state.index('brand-status-badge')).to be < state.index('brand-status-hint')
  end

  it "only explains the unreachable state" do
    block = script[/const hint = document\.getElementById\("brand-status-hint"\);.*?\n      \}/m]
    expect(block).not_to be_nil
    expect(block).to include('data.warning_type === "unreachable"')
    expect(block).to include('I18n.t("settings.brand.hint.unreachable")')
    expect(block).to include('hint.style.display = "none"')
  end

  it "wraps the copy in locale-appropriate brackets" do
    block = script[/const note = I18n\.t\("settings\.brand\.hint\.unreachable"\);\n.*?hint\.textContent.*?\n/m]
    expect(block).to include('I18n.lang() === "zh" ? `（${note}）` : `(${note})`')
  end

  it "ships the hint copy in both locales" do
    en = i18n[/"settings\.brand\.hint\.unreachable":\s*"([^"]+)"/, 1]
    zh = i18n.scan(/"settings\.brand\.hint\.unreachable":\s*"([^"]+)"/).flatten.last

    expect(en).to include("keeps working", "check your network")
    expect(zh).to include("功能暂不受影响", "请检查网络", "更换序列号")
    expect(zh).not_to eq(en)
  end

  it "keeps brackets out of the translations" do
    texts = i18n.scan(/"settings\.brand\.hint\.unreachable":\s*"([^"]+)"/).flatten
    expect(texts.size).to eq(2)
    texts.each do |text|
      expect(text).not_to start_with("（", "(")
      expect(text).not_to end_with("）", ")")
    end
  end

  it "renders the unreachable badge as a warning, not as plain text" do
    rule = styles[/\.badge-unreachable\s*\{[^}]*\}/]
    expect(rule).to include("var(--color-warning)")
    expect(rule).not_to include("--color-text-secondary")
  end

  it "styles the hint in the same warning color as the badge" do
    rule = styles[/\.brand-status-hint\s*\{[^}]*\}/]
    expect(rule).to include("font-size: 0.75rem", "var(--color-warning)")
    expect(rule).not_to include("--color-text-secondary")
  end
end
