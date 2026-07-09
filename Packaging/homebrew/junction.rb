# Homebrew cask for Junction.
#
# Lives in your tap repo: github.com/jnahian/homebrew-tap → Casks/junction.rb
# After each release: update `version` and `sha256` (printed in the release
# workflow log and on the release page), then push the tap.
#
# Until builds are notarized, users install with:
#   brew tap jnahian/tap
#   brew install --cask --no-quarantine junction
cask "junction" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/jnahian/junction/releases/download/v#{version}/Junction.zip"
  name "Junction"
  desc "Rule-based link router — routes links to the right browser, profile, or app"
  homepage "https://github.com/jnahian/junction"

  depends_on macos: ">= :ventura"

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
