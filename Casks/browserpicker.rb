cask "browserpicker" do
  version "0.3.0"
  sha256 "8d32641fa975d0f6b88ec23b75e1a517838728fe011c2da87b1ad3afb39d27aa"

  url "https://github.com/spashii/browserpicker/releases/download/v#{version}/BrowserPicker-#{version}.zip"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  auto_updates true
  depends_on macos: :ventura

  app "Browser Picker.app"

  zap trash: "~/.config/browserpicker"
end
