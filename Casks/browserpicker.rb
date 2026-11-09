cask "browserpicker" do
  version "0.4.0"
  sha256 "4eeb4625e645f792be1bf0aca70a43e52588057189473ef39967ff1001d38117"

  url "https://apps.idea2prod.in/browserpicker/download/#{version}"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  auto_updates true
  depends_on macos: :ventura

  app "Browser Picker.app"

  zap trash: "~/.config/browserpicker"
end
