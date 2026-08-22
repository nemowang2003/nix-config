{lib}: {
  mirror-options = {
    upstream,
    excluded,
  }:
    lib.genAttrs
    (lib.filter (name: !lib.elem name excluded) (lib.attrNames upstream))
    (name:
      lib.mkOption ({
          inherit (upstream.${name}) type default description;
        }
        // lib.optionalAttrs (upstream.${name} ? defaultText) {
          inherit (upstream.${name}) defaultText;
        }
        // lib.optionalAttrs (upstream.${name} ? example) {
          inherit (upstream.${name}) example;
        }));
}
