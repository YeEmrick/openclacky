# frozen_string_literal: true

# Saving the search provider succeeds silently in the panel, so the confirmation
# is a toast like every other settings action. Failures stay inline: the error
# text needs to sit next to the fields the user has to fix.
RSpec.describe "Search settings save feedback" do
  let(:settings_js) { File.read(File.expand_path("../../../lib/clacky/web/settings.js", __dir__)) }

  def save_handler
    body = settings_js[/saveBtn\.addEventListener\("click", async \(\) => \{(.*?)\n      \}\);/m, 1]
    raise "search save handler not found in settings.js" unless body

    body.gsub(/\s+/, " ")
  end

  it "confirms a successful save with a toast instead of inline text" do
    body = save_handler

    expect(body).to include('Modal.toast(I18n.t("settings.search.saved"), "success");')
    expect(body).not_to include('_showStatus(I18n.t("settings.search.saved")')
  end

  it "keeps failures inline so the message stays next to the fields" do
    body = save_handler

    expect(body).to include('_showStatus(data.error || I18n.t("settings.search.failed"), false);')
    expect(body).to include('_showStatus(e.message || I18n.t("settings.search.failed"), false);')
  end

  it "blocks saving a script searcher with no API key" do
    body = save_handler

    expect(body).to include('provider !== DS_WEB && !key')
    expect(body).to include('_showStatus(I18n.t("settings.search.keyRequired"), false);')
    expect(body).not_to include("Modal.confirm")
  end

  # app.css only defines .result-ok / .result-fail / .result-testing; the older
  # "success" / "error" suffixes silently rendered as plain body text.
  it "styles inline results with classes app.css actually defines" do
    expect(settings_js).to include('`model-test-result ${ok ? "result-ok" : "result-fail"}`')
    expect(settings_js).not_to match(/model-test-result (?:success|error)"/)
  end

  it "clears a stale result when the provider changes" do
    sync = settings_js[/function _syncKeyVisibility\(\) \{(.*?)\n    \}\n/m, 1]
    raise "_syncKeyVisibility not found in settings.js" unless sync

    expect(sync.gsub(/\s+/, " ")).to include('status.textContent = ""')
  end
end
