#!/bin/bash
# Prints the Homebrew cask for a release. It goes in Casks/opa-notch.rb in the
# 609-RESEARCH/homebrew-tap repository.
#
# Usage: scripts/generate-cask.sh <version> <path to opa.notch.dmg>
set -euo pipefail

VERSION="$1"
SHA256="$(shasum -a 256 "$2" | cut -d' ' -f1)"

cat <<CASK
cask "opa-notch" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/609-RESEARCH/opa.notch/releases/download/v#{version}/opa.notch.dmg"
  name "opa.notch"
  desc "Your day and your reminders in the MacBook notch"
  homepage "https://github.com/609-RESEARCH/opa.notch"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "opa.notch.app"

  uninstall quit: "app.opa.notch"

  zap trash: [
    "~/Library/Application Scripts/app.opa.notch",
    "~/Library/Containers/app.opa.notch",
  ]

  caveats <<~EOS
    opa.notch isn't notarized yet. On first launch, approve it in
    System Settings > Privacy & Security > Open Anyway.
  EOS
end
CASK
