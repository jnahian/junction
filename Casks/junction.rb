# Homebrew cask for Junction.
#
# This repo doubles as its own tap (Casks/ at the repo root). The release
# workflow bumps `version` and `sha256` here automatically on each tagged release.
#
# Until builds are notarized, macOS quarantines the app whatever Homebrew does,
# so installing takes a follow-up xattr (see caveats).
cask "junction" do
  version "0.4.3"
  sha256 "ae016e12e231896f0a1d496c70595ebe90fd2729f7cb9247738d6f9f589ba4b3"

  url "https://github.com/jnahian/junction/releases/download/v#{version}/Junction.dmg"
  name "Junction"
  desc "Rule-based link router — routes links to the right browser, profile, or app"
  homepage "https://github.com/jnahian/junction"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Junction.app"
  binary "#{appdir}/Junction.app/Contents/Helpers/junction"

  caveats <<~EOS
    Junction is not yet notarized, so macOS will block the first launch until you
    clear the quarantine flag:
      xattr -dr com.apple.quarantine "#{appdir}/Junction.app"
  EOS

  zap trash: [
    "~/.config/junction",
    "~/Library/Preferences/com.jnahian.junction.plist",
  ]
end
