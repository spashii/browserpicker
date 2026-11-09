cask "browserpicker" do
  version "0.5.0"
  sha256 "d8786841cd99901afc2d5d0a4f89f5c744dea038e4b6150bdf2f633fa795a00c"

  url "https://apps.idea2prod.in/browserpicker/download/#{version}"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  auto_updates true
  depends_on macos: :ventura

  app "Browser Picker.app"

  zap trash: "~/.config/browserpicker"
end
