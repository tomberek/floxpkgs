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
    output = (listToAttrs (map output_func list_newline));
    info = (mapAttrs info_func output);
    tiles = (mapAttrs tiles_func output);


    # Short pipeline
    short_list = lib.take 10 list_newline;
    output_short = (listToAttrs (map output_func short_list));
    info_short = (mapAttrs info_func output_short);
    tiles_short_pre = (mapAttrs tiles_func output_short);
    tiles_short = tiles_short_pre;

      symlinkJoin =
    args_@{ name
         , paths
         , preferLocalBuild ? true
         , allowSubstitutes ? false
         , postBuild ? ""
         , ...
         }:
    let
      args = removeAttrs args_ [ "name" "postBuild" ]
        // {
          inherit preferLocalBuild allowSubstitutes;
          passAsFile = [ "paths" ];
        }; # pass the defaults
    in runCommand name args
      ''
        mkdir -p $out
        find $(cat $pathsPath) -iname "*.png" | cut -d/ -f 5- | sort | uniq > file.list
        cat $pathsPath | tr $'\n' ' ' > path0.list
        cat $pathsPath | tr ' ' $'\n' > path.list
        while IFS= read -r line; do
          mkdir -p $(dirname $out/$line)
          find $(cat path.list | sed -e 's#$#/'"$line#" ) 2>/dev/null > $out/$line
        done < file.list || true
      '';

     func_combine = total_short: name: runCommand "${name}-0.1" {
        buildInputs = [ gdal imagemagick parallel ];
        } ''
          run(){
            output=$(echo $1 | cut -d/ -f5-)
            mkdir -p $(dirname $out/$output)
            convert $(cat $1) -background None -layers Flatten $out/$output
          }
          export -f run
          find ${total_short} -iname "*.png" | \
           parallel --ungroup -v --will-cite -N1 run {}
          cat ${builtins.elemAt (builtins.attrValues tiles_short) 0}/openlayers.html | grep -v extent > $out/openlayers.html
          '';

     total_short = symlinkJoin {
       name = "total-short-0.1";
       paths = attrValues tiles_short;
     };
     total = symlinkJoin {
       name = "total-0.1";
       paths = attrValues tiles;
     };
     total_final = func_combine total "total-final";
     total_final_short = func_combine total_short "total-final-short";


in lib.recurseIntoAttrs (builtins.mapAttrs (n: v: lib.recurseIntoAttrs v ) {
  inherit list output info tiles total total_short total_final total_final_short;
})
