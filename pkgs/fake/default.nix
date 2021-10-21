{ pkgs ? import <nixpkgs>{}, ...
}:
with builtins;
with pkgs;

let bucket = "radarsat-r1-l1-cog";
    prefix = "2013/";
    safeName = pname: let
      parts = split "[^a-zA-z0-9_-]" pname;
      non-null = filter (x: x != null && ! isList x && x != "") parts;
    in concatStringsSep "-" (non-null);
in
  rec {
    list = runCommand "fake" {
      buildInputs = [ awscli ];
      outputHashMode = "flat";
      outputHashAlgo = "sha256";
      outputHash = "sha256-biud3huZwctLkW5zDKnaEbNoeIZHRvp1i6trWVJDei4=";
    } ''
      aws --no-sign-request --output json s3api list-objects --bucket ${bucket} --prefix ${prefix} > $out
    '';
    list_keys = runCommand "list_keys" {
      buildInputs = [ awscli jq ];
    } ''
      jq '.Contents[].Key' ${list} -cr > output
      head -n10 output | tee $out
    '';

##### END OF BOILERPLATE #######

    # import-from-derivation
    output = let
      list_newline = lib.strings.splitString "\n" (readFile list_keys);
      func = key: {
        name = safeName key;
        value = runCommand "${safeName key}.tiff" {
          buildInputs = [ awscli ];
          __noChroot = true;
          } ''
          aws --no-sign-request s3 cp s3://${bucket}/${key} $out
        '';
      };
      in listToAttrs (map func list_newline);

    info = let
      func = key: value:
        runCommand "${safeName key}.tiff" {
          buildInputs = [ gdal ];
          } ''
            gdalinfo -json ${value} | tee $out
        '';
      in mapAttrs func output;

    tiles = let
      func = key: value:
        runCommand "${safeName key}" {
          buildInputs = [ gdal ];
          } ''
            gdal_translate -of VRT -ot Byte -scale ${value} temp.vrt
            gdal2tiles.py --xyz -z 5- temp.vrt $out
        '';
      in mapAttrs func output;

     total = buildEnv {
       name = "tiles";
       paths = attrValues tiles;
       checkCollisionContents = false;
       ignoreCollisions = true;
     };

  }
