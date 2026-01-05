{
  config,
  pkgs,
  name,
  lib,
  ...
}:
let
  inherit (lib)
    literalExpression
    mkDefault
    mkIf
    mkMerge
    mkOption
    types
    ;

  inherit (pkgs) formats;

  filename =
    let
      basename = builtins.baseNameOf name;
    in
    if basename != "" then basename else "root-file";

  topLevelFormats = [
    "json"
    "toml"
    "yaml"
  ];
  formatValues = [ config.generate.value ] ++ map (format: config.${format}) topLevelFormats;
in
{
  options = {
    source = mkOption {
      description = "Path of the source file or directory";
      type = types.path;
    };

    generate = {
      value = mkOption {
        description = "The attribute set to generate a file out of";
        type = with types; nullOr attrs;
        default = null;
      };

      format = mkOption {
        description = ''
          The format to use for turning `value` into a file.

          Formats can be found in `pkgs.formats`, and they must be called 
          before using them like so: `pkgs.formats.<format> { }`
        '';
        type = with types; nullOr attrs;
        default = null;
        example = literalExpression "pkgs.formats.toml { }";
      };

      generator = mkOption {
        description = ''
          A function that when called with the `value` attribute set returns
          a derivation of a text file that will be used for this path.

          This is an alternative, more fine grained alternative to using `format`,
          and `format` gets internally converted to this option
        '';
        type = with types; nullOr (functionTo package);
        default = null;
        example = literalExpression ''
          value: pkgs.writeText "my-json-config" (builtins.toJSON value)
        '';
      };
    };

    json = mkOption {
      description = "An attribute set to turn into a JSON file to be used as a source";
      type = types.nullOr (formats.json { }).type;
      default = null;
    };

    toml = mkOption {
      description = "An attribute set to turn into a TOML file to be used as a source";
      type = types.nullOr (formats.toml { }).type;
      default = null;
    };

    yaml = mkOption {
      description = "An attribute set to turn into a YAML file to be used as a source";
      type = types.nullOr (formats.yaml { }).type;
      default = null;
    };

    text = mkOption {
      description = ''
        Text that will be put in the resulting file. This is an
        alternative to using `source`, where `source` takes precedent.
      '';
      type = with types; nullOr lines;
      default = null;
    };

    executable = mkOption {
      description = ''
        Whether the file should be given execute permissions.
        If null, uses the permission of the source file.
      '';
      type = with types; nullOr bool;
      default = null;
    };
  };

  config = {
    generate = {
      format = mkMerge (
        map (type: mkIf (config.${type} != null) (mkDefault (formats.${type} { }))) topLevelFormats
      );

      generator = lib.mkDefault (config.generate.format.generate filename);
    };

    source =
      let
        setValues = builtins.filter (value: value != null) formatValues;
        numSetValues = builtins.length setValues;
        finalValue =
          if numSetValues == 0 then
            null
          else if numSetValues == 1 then
            builtins.head setValues
          else
            throw ''
              Multiple generatable values set for wrapper path ${name}, please set at most one.
            '';
        generatedSource = config.generate.generator finalValue;
        textSource = pkgs.writeTextFile {
          inherit (config) text;
          executable = config.executable == true;
          name = filename;
        };
      in
      mkMerge [
        (mkIf (finalValue != null) (mkDefault generatedSource))
        (mkIf (config.text != null) (mkDefault textSource))
      ];
  };
}
