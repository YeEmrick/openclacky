# frozen_string_literal: true

RSpec.describe "Brand support QR lightbox" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:markup)  { File.read(File.join(web_dir, "index.html")) }
  let(:i18n)    { File.read(File.join(web_dir, "i18n.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }

  def rem(rule, prop)
    value = rule[/\b#{prop}:\s*([\d.]+)rem/, 1]
    value ||= rule[/\bpadding:\s*([\d.]+)rem/, 1]
    expect(value).not_to be_nil, "expected #{prop} in #{rule}"
    value.to_f
  end

  it "localizes the default caption instead of hardcoding English" do
    label = markup[/<p class="qr-lightbox-label" id="qr-lightbox-label".*?<\/p>/m]
    expect(label).to include('data-i18n="settings.brand.label.supportQr"')
  end

  it "translates that caption in both locales" do
    en = i18n[/"settings\.brand\.label\.supportQr":\s*"([^"]+)"/, 1]
    zh = i18n.scan(/"settings\.brand\.label\.supportQr":\s*"([^"]+)"/).flatten.last

    expect(en).to eq("Tech Support")
    expect(zh).to eq("技术支持")
  end

  it "keeps the close button clear of the content below it" do
    content = styles[/\.qr-lightbox-content\s*\{[^}]*\}/]
    close   = styles[/\.qr-lightbox-close\s*\{[^}]*\}/]

    close_bottom = rem(close, "top") + rem(close, "height")
    expect(rem(content, "padding-top")).to be > close_bottom
  end
end
