{lib}: let
  mirrored-fields = [
    "type"
    "default"
    "defaultText"
    "description"
    "example"
    "internal"
    "readOnly"
    "visible"
  ];

  mirror-option = option:
    lib.mkOption (
      lib.getAttrs
      (lib.filter (name: builtins.hasAttr name option) mirrored-fields)
      option
    );
in {
  mirror-options = {
    upstream,
    excluded,
  }:
    lib.genAttrs
    (lib.filter (name: !lib.elem name excluded) (lib.attrNames upstream))
    (name: mirror-option upstream.${name});
}
