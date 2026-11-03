cask "browserpicker" do
  version "0.2.0"
  sha256 "be9ca42639786df27b39259f314fab8a49f97e832d33b0ec5edf6f28e45623cf"

  url "https://github.com/spashii/browserpicker/releases/download/v#{version}/BrowserPicker-#{version}.zip"
  name "Browser Picker"
  desc "Asks which browser or profile a link should open in"
  homepage "https://github.com/spashii/browserpicker"

  depends_on macos: :ventura

  app "Browser Picker.app"

  # Ad-hoc signed, so drop the quarantine flag instead of making people right-click Open.
  postflight_steps [
    {
      type:    "run",
      command: { path: "/usr/bin/xattr" },
      args:    ["-dr", "com.apple.quarantine", "{{appdir}}/Browser Picker.app"],
    },
  ]

  zap trash: "~/.config/browserpicker"
end
