# Homebrew cask for Junction.
#
# This repo doubles as its own tap (Casks/ at the repo root). The release
# workflow bumps `version` and `sha256` here automatically on each tagged release.
#
# Until builds are notarized, users install with:
#   brew tap jnahian/junction https://github.com/jnahian/junction
#   brew install --cask --no-quarantine junction
cask "junction" do
  version "0.2.0"
  sha256 "3700a3f7f1b6ea677643af44ebcc21f3d90ade4ef679530c7fa1396e6b9ed63c"

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
