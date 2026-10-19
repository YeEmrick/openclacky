# frozen_string_literal: true

# Free is the safe default on a fresh install, so it leads the list. DeepSeek
# follows and only wins the selection when a model key makes it usable.
RSpec.describe "Web search provider order" do
  let(:settings_js) { File.read(File.expand_path("../../../lib/clacky/web/settings.js", __dir__)) }
  let(:index_html)  { File.read(File.expand_path("../../../lib/clacky/web/index.html", __dir__)) }

  it "lists the free chain before DeepSeek in the rendered dropdown" do
    body = settings_js.scan(/dropdown\.innerHTML\s*=(.*?);/m)
                      .flatten
                      .find { |chunk| chunk.include?("deepseekRow") }

    expect(body).not_to be_nil
    expect(body.index("settings.search.builtin")).to be < body.index("deepseekRow")
  end

  it "keeps the static markup in the same order" do
    start = index_html.index('id="settings-search-provider-dropdown"')
    dropdown = index_html[start, 800]

    expect(dropdown.index('data-value=""')).to be < dropdown.index('data-value="deepseek_web"')
  end
end
