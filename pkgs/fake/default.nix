{ pkgs, ...
#{ pkgs ? import <nixpkgs>{}, ...
}:
with builtins;
with pkgs;

let
    # bucket = "radarsat-r1-l1-cog";
    # prefix = "2013/";
    bucket = "deafrica-landsat";
    prefix = "collection02/level-2/standard/etm/2021/158/";
    region = "af-south-1";
    safeName = pname: let
      parts = split "[^a-zA-z0-9_-]" pname;
      non-null = filter (x: x != null && ! isList x && x != "") parts;
    in concatStringsSep "-" (non-null);

    list = runCommand "list.json" {
      buildInputs = [ awscli ];
      outputHashMode = "flat";
      outputHashAlgo = "sha256";
      outputHash = "sha256-qE2eDLzTbNX5nSRZtNFg9pthfMSvZe+nUODu2zMxlr4=";
    } ''
      aws --no-sign-request --output json s3api list-objects --region ${region} --bucket ${bucket} --prefix ${prefix} > $out
    '';
    list_keys = runCommand "list_keys.txt" {
      buildInputs = [ awscli jq ];
    } ''
      jq '.Contents[].Key' ${list} -cr > output
      cat output | grep 'PIXEL\.TIF$' | awk -F'/' '{if(!($6$7 in a)) print $0;a[$6$7]=1}' | tee $out
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
        aws --no-sign-request s3 --region ${region} cp s3://${bucket}/${key} $out
      '';
    };

    info_func = key: value:
      runCommand "${safeName key}.json" {
        buildInputs = [ gdal ];
        } ''
          gdalinfo -json ${value} | tee $out
      '';

    tiles_func = key: value:
        runCommand "${safeName key}" {
          buildInputs = [ gdal ];
          } ''
            gdal_translate -of VRT -ot Byte -scale ${value} ${key}.vrt
            gdal2tiles.py --xyz -z 5-13 ${key}.vrt $out
        '';


    # Full pipeline
    output = lib.recurseIntoAttrs (listToAttrs (map output_func list_newline));
    info = lib.recurseIntoAttrs (mapAttrs info_func output);
    tiles = lib.recurseIntoAttrs (mapAttrs tiles_func output);


    # Short pipeline
    short_list = lib.take 4 list_newline;
    output_short = (listToAttrs (map output_func short_list));
    info_short = (mapAttrs info_func output_short);
    tiles_short_pre = (mapAttrs tiles_func output_short);
    tiles_short = tiles_short_pre;

     total_short = buildEnv {
       name = "total-short-0.0";
       paths = attrValues tiles_short;
       checkCollisionContents = false;
       ignoreCollisions = true;
     };

     total = buildEnv {
       name = "total-0.1";
       paths = attrValues tiles;
       checkCollisionContents = false;
       ignoreCollisions = true;
     };
     farm = linkFarmFromDrvs "farm-0.0" (attrValues tiles);
     farm_short = linkFarmFromDrvs "farm-0.0" (attrValues tiles_short_pre);


in lib.recurseIntoAttrs {
  inherit list output info tiles total total_short farm farm_short;
}
