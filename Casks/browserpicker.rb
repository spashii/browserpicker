cask "browserpicker" do
  version "0.5.1"
  sha256 "13b1636566cce054c948c22a8db88098f8dcf81251fbc4e6652a5ed79da924fe"

  url "https://apps.idea2prod.in/browserpicker/download/#{version}"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  auto_updates true
  depends_on macos: :ventura

  app "Browser Picker.app"

  zap trash: "~/.config/browserpicker"
end
