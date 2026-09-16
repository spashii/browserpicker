cask "browserpicker" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/spashii/browserpicker/releases/download/v#{version}/BrowserPicker-#{version}.zip"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  depends_on macos: ">= :ventura"

  app "Browser Picker.app"

  # Ad-hoc signed, so drop the quarantine flag instead of making people right-click Open.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Browser Picker.app"],
                   sudo: false
  end

  zap trash: "~/.config/browserpicker"
end
