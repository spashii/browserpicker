cask "browserpicker" do
  version "0.3.1"
  sha256 "886f6fc5e4c526b97f0032634cc181edd10bde098f3fff586399f43069047de9"

  url "https://apps.idea2prod.in/browserpicker/download/#{version}"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  auto_updates true
  depends_on macos: :ventura

  app "Browser Picker.app"

  zap trash: "~/.config/browserpicker"
end
