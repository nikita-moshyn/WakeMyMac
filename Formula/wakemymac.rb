class Wakemymac < Formula
  desc "Prevent Mac from sleeping with configurable wake sessions"
  homepage "https://github.com/nikita-moshyn/WakeMyMac"
  url "https://github.com/nikita-moshyn/WakeMyMac/releases/download/v2.1.1/WakeMyMac_2.1.1.tar.gz"
  version "2.1.1"
  sha256 "b3183330d6e11593a9e6fe7664c187c18c9f86858d4efb95eddf56bb7b85330f"
  license "Apache-2.0"

  bottle do
    root_url "https://github.com/nikita-moshyn/WakeMyMac/releases/download/v2.1.1"
    sha256 cellar: :any_skip_relocation, arm64_sonoma: "17f4f526f8c72af898c02019d2b1c53bab28520b245f07405c1b87782594f4ed"
    sha256 cellar: :any_skip_relocation, sonoma: "17f4f526f8c72af898c02019d2b1c53bab28520b245f07405c1b87782594f4ed"
  end

  depends_on :macos

  def install
    bin.install "WakeMyMac_universal" => "wake"
  end

  test do
    system "#{bin}/wake", "--version"
  end
end
