class Wakemymac < Formula
  desc "CLI tool to prevent Mac from sleeping, energy-efficient sleep prevention."
  homepage "https://github.com/mnmn13/WakeMyMac"
  url "https://github.com/mnmn13/WakeMyMac/releases/download/v2.1.0/WakeMyMac_2.1.0.tar.gz"
  sha256 "692ccd8508d93598adfdfefd392ce4dc79a046ee218960e7a252f55c7b069fa5"
  license "Apache-2.0"
  version "2.1.0"

  def install
    bin.install "WakeMyMac_universal" => "wake"
  end
  
  def caveats
    <<~EOS
        export PATH="/usr/local/bin:$PATH"
        source ~/.zshrc
    EOS
  end

  test do
    system "#{bin}/wake", "--version"
  end
end
