# Homebrew cask for the tap at this repository:
#   brew tap vflame6/uncial https://github.com/vflame6/uncial
#   brew install --cask uncial
# `make release` rewrites the version and the checksum for every release.
cask "uncial" do
  version "1.1.4"
  sha256 "099403df4f682c4f710315023f6917708f8594b021b936c1a884e9239bf11b12"

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
    "~/Library/Application Scripts/com.maksimradaev.uncial.QuickLook",
    "~/Library/Application Scripts/com.maksimradaev.uncial.Thumbnail",
    "~/Library/Application Scripts/XWTLHG45H7.com.maksimradaev.uncial",
    "~/Library/Caches/com.maksimradaev.uncial",
    "~/Library/Containers/com.maksimradaev.uncial.QuickLook",
    "~/Library/Containers/com.maksimradaev.uncial.Thumbnail",
    "~/Library/Group Containers/XWTLHG45H7.com.maksimradaev.uncial",
    "~/Library/HTTPStorages/com.maksimradaev.uncial",
    "~/Library/HTTPStorages/com.maksimradaev.uncial.binarycookies",
    "~/Library/Preferences/com.maksimradaev.uncial.plist",
    "~/Library/WebKit/com.maksimradaev.uncial",
  ]

  caveats <<~EOS
    Uncial is signed with a development certificate and not notarized, so macOS blocks
    the first launch: allow it under System Settings > Privacy & Security ("Open Anyway").

    Open Uncial once so macOS registers its Quick Look extensions. If Space in Finder
    still shows Markdown as plain text, enable "Uncial Quick Look" and "Uncial Thumbnails"
    under System Settings > General > Login Items & Extensions > Quick Look and run
      qlmanage -r && qlmanage -r cache
  EOS
end
