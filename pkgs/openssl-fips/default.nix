{ pkgs, ...
}:

pkgs.openssl_3_0.overrideAttrs (old: {

      configureFlags = ["enable-fips"] ++ old.configureFlags ;
    })
