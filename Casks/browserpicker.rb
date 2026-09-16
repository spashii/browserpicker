cask "browserpicker" do
  version "0.1.0"
  sha256 "ef13239ddc0b60d549321620c097c98063271fac35e69fdef39be0d4f93d8cd3"

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
