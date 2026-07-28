{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) literalExpression mkOption types;

  # We want to pass pname + version if possible for better metadata, but not all
  # packages have pname + version, only name
  wrapperNameSet =
    if config.package ? pname && config.package ? version then
      {
        pname = config.package.pname + "-wrapped";
        version = config.package.version;
      }
    else
      {
        name = config.package.name + "-wrapped";
      };

  wrapperName = wrapperNameSet.name or "${wrapperNameSet.pname}-${wrapperNameSet.version}";

  fileBuilderType = types.attrsOf (
    types.attrsOf (
      types.submodule [
        ./path-options.nix
        { _module.args.pkgs = pkgs; }
      ]
    )
  );
  pathConstructor = pkgs.callPackage ./path-constructor.nix { };
  mkEnvVarOption =
    description:
    mkOption {
      description = ''
        ${description}

                The value of each variable can be either a string, integer, path,
                or a list of the aforementioned. A list will be concatenated with
                colon characters as separators.
      '';
      default = { };
      type =
        with types;
        attrsOf (oneOf [
          (listOf (oneOf [
            int
            str
            path
          ]))
          int
          str
          path
        ]);
      # Turn values passed to strings, concatenate lists with ":" as separators,
      # and copy paths to the store
      apply =
        let
          # Copy paths to store by string interpolation
          toStr = v: if lib.isPath v then "${v}" else toString v;
        in
        lib.mapAttrs (_: v: if lib.isList v then (lib.concatMapStringsSep ":" (toStr v)) else toStr v);
    };

  generalOptionsSet = {
    package = mkOption {
      description = "The package to wrap";
      type = types.package;
      example = literalExpression "pkgs.hello";
    };

    result = mkOption {
      description = "The resulting wrapped package (read only)";
      type = types.package;
      readOnly = true;
    };

    useBinaryWrapper = mkOption {
      description = ''
        Whether to use `makeBinaryWrapper` instead of `makeWrapper` to create the wrapper.

        `makeWrapper` is required if the wrapper needs some shell features (such as looking up environment
        variables at runtime) or its unique arguments. More Info about their differences
        [here](https://nixos.org/manual/nixpkgs/unstable/#:~:text=Using%20the%20makeBinaryWrapper%20implementation)
      '';
      type = types.bool;
      example = true;
    };

    extraMakeWrapperArgs = mkOption {
      description = ''
        A list of extra arguments to pass to `make[Binary]Wrapper`.
      '';
      type = with types; listOf str;
      default = [ ];
      example = literalExpression ''
        [
          "--chdir" "/nix/store"
          "--set-default" "XDG_CACHE_HOME" "/tmp"
        ]
      '';
    };

    excludeBins = mkOption {
      description = ''
        List of files in $out/bin/ to not wrap. Can not be set if `includeBins`
        is set.
      '';
      type = with types; listOf str;
      default = [ ];
      example = [ "kitten" ];
    };

    includeBins = mkOption {
      description = ''
        List of files in $out/bin/ to wrap, wraps everything by default. Can not
        be set if `excludeBins` is set.
      '';
      type = with types; listOf str;
      default = [ ];
      example = [ "kitty" ];
    };

    includeAbsolute = mkOption {
      description = "Also include binaries in this path relative from $out";
      type = with types; listOf str;
      default = [ ];
      example = [ "libexec/scdaemon" ];
    };

    flags = {
      normal = mkOption {
        description = ''
          A list of flags and/or args that the wrapper will always pass to the wrapped executable
        '';
        type = with types; listOf str;
        default = [ ];
        example = literalExpression ''
          [
            "-c"
            "--binary ''${lib.getExe pkgs.hello}"
          ]
        '';
      };

      path = mkOption {
        description = ''
          Attribute set with keys as the flags and values as the definition
          of a store path that will be passed with the flag, ie.
          `--config-dir <defined store path>`

          The value should be an attribute set where each key is the name of a
          file in the resulting directory, and "/" is the special name to define
          the store path to be a single link to something with `source`, or
          a single file with `text`.

          The file can be declared to be in a subdirectory by setting the key name
          to resemble a path, ie. "lsp_configs/lsp.conf" will place a file in
          $out/lsp_configs/lsp.conf
        '';
        type = fileBuilderType;
        default = { };
        apply = builtins.mapAttrs (
          attrName: manifest: pathConstructor { inherit wrapperName attrName manifest; }
        );
        example = literalExpression ''
          {
            "--config-dir" = {
              "conf_file.conf".text = ''' # Define the text which will be placed in the file
                value1 = 1
                value2 = 2
              ''';
              "lsp_configs/lsp.conf".source = ./my_lsp_config; # Setting the source of a single file in a subdirectory
              plugins_dir.source = ./my_plugins; # Setting the source of an entire directory
            };

            "--config-file"."/".text = "this is just a single file";
          }
        '';
      };
    };

    env = {
      vars = mkEnvVarOption "Environment variables to set for the wrapper";

      # TODO: allow separating by other than ':'
      prefixes = mkEnvVarOption ''
        Environment variables to prefix with a ':' as the separator.

        ie. setting this to
        {
          PATH = "''${pkgs.hello}/bin";
        }

        would set `PATH = /nix/store/AAAAAAAAA-hello-1.0.0/bin:$PATH`.
      '';
      suffixes = mkEnvVarOption ''
        Environment variables to suffix with a ':' as the separator.

        ie. setting this to
        {
          PATH = "''${pkgs.hello}/bin";
        }

        would set `PATH = $PATH:/nix/store/AAAAAAAAA-hello-1.0.0/bin`.

        This can be used to set ie. fallback paths for when a binary
        from $PATH should be used if found, but otherwise use the one
        from the path specified here.
      '';

      paths = mkOption {
        description = ''
          Attribute set with keys as environment variable names and values as the
          definitions of store paths the variable will point to in the wrapper.

          The value should be an attribute set where each key is the name of a
          file in the resulting directory, and "/" is the special name to define
          the variable to point to just a file instead of a directory.

          The file can be declared to be in a subdirectory by setting the key name
          to resemble a path, ie. "lsp_configs/lsp.conf" will place a file in
          $out/lsp_configs/lsp.conf
        '';
        type = fileBuilderType;
        default = { };
        apply = builtins.mapAttrs (
          attrName: manifest: pathConstructor { inherit wrapperName attrName manifest; }
        );
        example = literalExpression ''
          {
            CONFIG_DIR = {
              "conf_file.conf".text = ''' # Define the text which will be placed in the file
                value1 = 1
                value2 = 2
              ''';
              "lsp_configs/lsp.conf".source = ./my_lsp_config; # Setting the source of a single file in a subdirectory
              plugins_dir.source = ./my_plugins; # Setting the source of an entire directory
            };

            CONFIG_FILE."/".text = "this is just a single file";
          }
        '';
      };
    };

    finalMakeWrapperArgs = mkOption {
      description = "final makeWrapper args to use";
      type = types.str;
      internal = true;
      readOnly = true;
    };

    # Needed to use assertions
    assertions = mkOption {
      type = with types; listOf unspecified;
    };
  };

  mkFinalMakeWrapperArgs =
    modConfig:
    let
      flags = {
        normal = map (flag: [
          "--add-flags"
          flag
        ]) modConfig.flags.normal;

        # A flag like `--config=<file>` must be one arg
        path = lib.mapAttrsToList (
          flag: value:
          if lib.hasSuffix "=" flag then
            [
              "--add-flags"
              "${flag}${value}"
            ]
          # nested list, it's ok since we flatten in the end
          else
            [
              "--add-flags"
              flag
              "--add-flags"
              value
            ]
        ) modConfig.flags.path;

      };

      collectArgs = args: lib.flatten (lib.attrValues args);
      flagArgs = collectArgs flags;

      # collectEnvVars =
      #   flagType: separator: vars:
      #   lib.concatMapAttrsStringSep " " (
      #     var: value: ''${flagType} "${escapeQuotes var}" ${separator} "${escapeQuotes value}" ''
      #   ) vars;

      collectEnvVars =
        flagType: separator: vars:
        lib.mapAttrsToList (
          var: value:
          [
            flagType
            var
          ]
          ++ lib.optional (separator != null) separator
          ++ [ value ]
        ) vars;
      env = {
        vars = collectEnvVars "--set" null modConfig.env.vars;
        paths = collectEnvVars "--set" null modConfig.env.paths;
        prefixes = collectEnvVars "--prefix" ":" modConfig.env.prefixes;
        suffixes = collectEnvVars "--suffix" ":" modConfig.env.suffixes;
      };

      envArgs = collectArgs env;

      makeWrapperArgs = lib.escapeShellArgs (flagArgs ++ envArgs ++ modConfig.extraMakeWrapperArgs);
    in
    makeWrapperArgs;
in
{
  options = generalOptionsSet // {
    bin = mkOption {
      description = "wrapping options to apply only to specific executable in package";
      type =
        with types;
        attrsOf (submodule [
          ({ config, ... }: {
            options = generalOptionsSet;
            config.finalMakeWrapperArgs = mkFinalMakeWrapperArgs config;
          })
        ]);
      default = { };
    };
  };

  config = {
    assertions = [
      {
        assertion = config.excludeBins == [ ] || config.includeBins == [ ];
        message = ''
          Only one of `excludeBins` and `includeBins` should be set.
        '';
      }
    ];

    finalMakeWrapperArgs = mkFinalMakeWrapperArgs config;

    result =
      let
        hasMan = builtins.elem "man" config.package.outputs;
        outputs = [ "out" ] ++ (lib.optional hasMan "man");
        makeWrapperPkg = if config.useBinaryWrapper then pkgs.makeBinaryWrapper else pkgs.makeWrapper;

        pathsPassthru = {
          envPaths = config.env.paths;
          flagPaths = config.flags.path;
          binPaths = builtins.mapAttrs (n: v: {
            envPaths = v.env.paths;
            flagPaths = v.flags.path;
          }) config.bin;
        };
        absoluteBins = lib.concatMapStringsSep " " (
          relpath: ''"$out"/${lib.escapeShellArg relpath}''
        ) config.includeAbsolute;
      in
      pkgs.symlinkJoin (
        wrapperNameSet
        // {
          inherit outputs;
          passthru = pathsPassthru // config.package.passthru;
          meta = config.package.meta // {
            outputsToInstall = outputs;
          };

          paths = [ config.package ];
          nativeBuildInputs = [ makeWrapperPkg ];
          postBuild = ''
            shouldWrap() {
              ${lib.toShellVar "includes" config.includeBins}
              ${lib.toShellVar "excludes" config.excludeBins}
              local bin="''${1##*/}"

              if [[ ''${#includes[@]} -gt 0 ]]; then
                for elem in "''${includes[@]}"; do
                  [[ "$bin" == "$elem" ]] && return 0
                done

                return 1
              fi

              if [[ ''${#excludes[@]} -gt 0 ]]; then
                for elem in "''${excludes[@]}"; do
                  [[ "$bin" == "$elem" ]] && return 1
                done

                return 0
              fi

              return 0
            }

            for bin in "$out"/bin/*; do
              [[ -x "$bin" ]] || continue
              shouldWrap "$bin" || continue

              name=''${bin##*/}
              args=(${config.finalMakeWrapperArgs})
              ${lib.concatMapAttrsStringSep "\n" (n: v: /* bash */ ''
                if [[ "$name" == "${n}" ]]; then
                  args+=(${v.finalMakeWrapperArgs})
                fi
              '') config.bin}
              wrapProgram "$bin" "''${args[@]}"
            done

            for bin in ${absoluteBins}; do
              [[ -x "$bin" ]] || continue
              name=''${bin##*/}
              args=(${config.finalMakeWrapperArgs})
              ${lib.concatMapAttrsStringSep "\n" (n: v: /* bash */ ''
                if [[ "$name" == "${n}" ]]; then
                  args+=(${v.finalMakeWrapperArgs})
                fi
              '') config.bin}
              wrapProgram "$bin" "''${args[@]}"
            done

            ${lib.optionalString hasMan ''
              cp -rs "${config.package.man}" $man
            ''}

            # Replace references to the wrapped package in desktop and systemd files
            for file in $out/share/applications/*.desktop \
                        $out/lib/systemd/system/* \
                        $out/lib/systemd/user/*; do
              grep -q "${config.package}" "$file" || continue
              cp --remove-destination "$(realpath "$file")" "$file"
              substituteInPlace "$file" \
                --replace-fail "${config.package}" "$out"
            done
          '';
        }
      );
  };
}
