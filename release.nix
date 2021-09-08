/* A small release file, with few packages to be built.  The aim is to reduce
   the load on Hydra when testing the `stdenv-updates' branch. */

let
  nixpkgs ={ outPath = (import (<nixpkgs> + "/lib")).cleanSource <nixpkgs>; revCount = 1234; shortRev = "abcdef"; };
supportedSystems = [ "x86_64-linux" ];
 # Attributes passed to nixpkgs. Don't build packages marked as unfree.
  nixpkgsArgs = { config = { allowUnfree = false; inHydra = true; }; };
    relib = (import (<nixpkgs> + "/pkgs/top-level/release-lib.nix")) { inherit supportedSystems nixpkgsArgs; };
in
  with relib;
{

  tarball = import (<nixpkgs> + "/pkgs/top-level/make-tarball.nix") {
    inherit nixpkgs supportedSystems;
    officialRelease = false;
  };

} // (mapTestOn {

}) // (with builtins; let
  file = fromTOML (readFile ./packages.toml);
  filtered = lib.filterAttrs (k: v: v) file;
in
  mapTestOn (mapAttrs (k: v: getAttr "linux" relib ) filtered)
  )
  
