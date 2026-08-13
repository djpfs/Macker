cask "macker" do
  # Refresh version and sha256 after each stable release with:
  # ./Scripts/update-cask.sh v1.0.0.<run>
  version "1.0.0.9"
  sha256 "e6ef4ade4e8b06a116e669b5ee44903ccc4a44db27dd0b7f01a6510b52033f44"

  url "https://github.com/djpfs/Macker/releases/download/v#{version}/Macker-#{version}.pkg",
      verified: "github.com/djpfs/Macker/"
  name "Macker"
  desc "Docker Desktop replacement on Apple's native container runtime"
  homepage "https://github.com/djpfs/Macker"

  depends_on macos: :sequoia

  pkg "Macker-#{version}.pkg"

  uninstall pkgutil: "com.macker.app"

  zap trash: [
    "~/Library/Application Support/Macker",
    "~/Library/Preferences/com.macker.app.plist",
  ]
end
