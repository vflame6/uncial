# Homebrew cask for the tap at this repository:
#   brew tap vflame6/uncial https://github.com/vflame6/uncial
#   brew install --cask uncial
# `make release` rewrites the version and the checksum for every release.
cask "uncial" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/vflame6/uncial/releases/download/v#{version}/Uncial-#{version}.zip"
  name "Uncial"
  desc "Markdown reader and editor with Quick Look preview and thumbnail extensions"
  homepage "https://github.com/vflame6/uncial"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Uncial.app"

  uninstall quit: "com.maksimradaev.uncial"

  zap trash: [
    "~/Library/Containers/com.maksimradaev.uncial.QuickLook",
    "~/Library/Containers/com.maksimradaev.uncial.Thumbnail",
    "~/Library/Group Containers/XWTLHG45H7.com.maksimradaev.uncial",
    "~/Library/Preferences/com.maksimradaev.uncial.plist",
  ]

  caveats <<~EOS
    Open Uncial once so macOS registers its Quick Look extensions. If Space in Finder
    still shows Markdown as plain text, enable "Uncial Quick Look" and "Uncial Thumbnails"
    under System Settings > General > Login Items & Extensions > Quick Look and run
      qlmanage -r && qlmanage -r cache
  EOS
end
