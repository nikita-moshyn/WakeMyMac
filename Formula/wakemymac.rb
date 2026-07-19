class Wakemymac < Formula
  desc "CLI tool to prevent Mac from sleeping, energy-efficient sleep prevention."
  homepage "https://github.com/mnmn13/WakeMyMac"
  url "https://github.com/mnmn13/WakeMyMac/releases/download/v2.0.0/WakeMyMac_2.0.0.tar.gz"
  sha256 "9e42acbd1f69abd27fe392c84d2e2158a28f39ff9fcf1d0d72b536593a9bdf87"
  license "Apache-2.0"
  version "2.0.0"

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
