class Wakemymac < Formula
  desc "Prevent Mac from sleeping with configurable wake sessions"
  homepage "https://github.com/nikita-moshyn/WakeMyMac"
  url "https://github.com/nikita-moshyn/WakeMyMac/releases/download/v2.1.0/WakeMyMac_2.1.0.tar.gz"
  version "2.1.0"
  sha256 "692ccd8508d93598adfdfefd392ce4dc79a046ee218960e7a252f55c7b069fa5"
  license "Apache-2.0"

  depends_on :macos

  def install
    bin.install "WakeMyMac_universal" => "wake"
  end

  test do
    system "#{bin}/wake", "--version"
  end
end
