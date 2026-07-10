# Homebrew cask for Junction.
#
# This repo doubles as its own tap (Casks/ at the repo root). The release
# workflow bumps `version` and `sha256` here automatically on each tagged release.
#
# Until builds are notarized, users install with:
#   brew tap jnahian/junction https://github.com/jnahian/junction
#   brew install --cask --no-quarantine junction
cask "junction" do
  version "0.1.1"
  sha256 "d51a167e246a19880d823892b0ee5739ed2211842a83bb550b33291e1cbd44d7"

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
    Junction is not yet notarized. If macOS blocks the first launch, install with
    `brew install --cask --no-quarantine junction`, or run:
      xattr -dr com.apple.quarantine "#{appdir}/Junction.app"
  EOS

  zap trash: [
    "~/.config/junction",
    "~/Library/Preferences/com.jnahian.junction.plist",
  ]
end
