{ pkgs, ...
#{ pkgs ? import <nixpkgs>{}, ...
}:
with builtins;
with pkgs;

let bucket = "radarsat-r1-l1-cog";
    prefix = "2013/";
    safeName = pname: let
      parts = split "[^a-zA-z0-9_-]" pname;
      non-null = filter (x: x != null && ! isList x && x != "") parts;
    in concatStringsSep "-" (non-null);

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
      cat output | tee $out
    '';

##### END OF BOILERPLATE #######

    # import-from-derivation
    list_newline = filter (x: x != "" ) (lib.strings.splitString "\n" (readFile list_keys));

    output_func = key: {
      name = safeName key;
      value = runCommand "${safeName key}.tiff" {
        buildInputs = [ awscli ];
        __noChroot = true;
        } ''
        echo ${list_keys}
        aws --no-sign-request s3 cp s3://${bucket}/${key} $out
      '';
    };

    info_func = key: value:
      runCommand "${safeName key}.tiff" {
        buildInputs = [ gdal ];
        } ''
          gdalinfo -json ${value} | tee $out
      '';

    tiles_func = key: value:
        runCommand "${safeName key}" {
          buildInputs = [ gdal ];
          } ''
            gdal_translate -of VRT -ot Byte -scale ${value} temp.vrt
            gdal2tiles.py --xyz -z 5-13 temp.vrt $out
        '';


    # Full pipeline
    output = lib.recurseIntoAttrs (listToAttrs (map output_func list_newline));
    info = lib.recurseIntoAttrs (mapAttrs info_func output);
    tiles = lib.recurseIntoAttrs (mapAttrs tiles_func output);


    # Short pipeline
    short_list = lib.list.take 10 list_newline;
    output_short = lib.recurseIntoAttrs (listToAttrs (map output_func short_list));
    info_short = lib.recurseIntoAttrs (mapAttrs info_func output_short);
    tiles_short = lib.recurseIntoAttrs (mapAttrs tiles_func output_short);

     total = buildEnv {
       name = "total";
       paths = attrValues tiles;
       checkCollisionContents = false;
       ignoreCollisions = true;
     };


in lib.recurseIntoAttrs {
  inherit output info tiles total;
}
