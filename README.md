# wrapper-lib
This is a simple Nix library/framework for creating wrappers derivations around programs, that allow you to wrap
the programs with config files, flags, environment variables, etc.

## Installing
### Flakes
Just add the following to your inputs
```nix
wrapper-lib.url = "github:langsjo/wrapper-lib";
```
Then you can access the library like
```nix
wLib = wrapper-lib.lib;
```

### Channels
Add a Nix channel like so (may need to add it for the root user)
```bash
nix-channel --add https://github.com/langsjo/wrapper-lib/archive/main.tar.gz wrapper-lib
```
Then you can access the library like
```nix
wLib = (import <wrapper-lib>).lib;
```

### Builtin fetcher
```nix
let
  wrapper-lib = builtins.fetchTarball {
    # Change `<commit rev>` to desired commit rev
    url = "https://github.com/langsjo/wrapper-lib/archive/<commit rev>.tar.gz";
    # Change `<hash>` to the hash it spits out after first leaving it empty
    sha256 = "<hash>";
  };
  wLib = (import wrapper-lib).lib;
in
  ...
```

## Usage
This won't cover all the options the library provides, you can see [./wrapper-module.nix](./wrapper-module.nix) for all options,
as well as [./path-options.nix](./path-options.nix) for the options that the path type options accept

Wrapping Alacritty to use a specific config file
```nix
# default.nix
{ pkgs }:
let
  wLib = ...;
  mkWrapper = wLib.mkWrapper pkgs; # mkWrapper needs to be instantiated with a `pkgs` instance
in
{
  alacritty-wrapped = mkWrapper ./alacritty.nix;
}

# alacritty.nix
{
  alacritty, # Take as argument the `alacritty` package, comes from the `pkgs` instance
}:
{
  package = alacritty; # Wrapping `alacritty`

  # Always pass the `--config-file` flag with a path as an argument
  # The path is a single file (denoted by using "/"), that is in toml format
  flags.path."--config-file"."/".toml = {
    env.TERM = "xterm-256color";
    window = {
      decorations = "none";
      dynamic_padding = false;
      opacity = 1;
    };

    font = {
      size = "12";
      normal = {
        family = "MesloLGM Nerd Font";
        style = "Medium";
      };
    };

    colors.normal = {
      green = "#00AA00";
      red = "#FF0000";
      yellow = "#DDDD00";
      blue = "#1144CC";
      magenta = "#AA00AA";
      cyan = "#00AAAA";
      white = "#DDDDDD";
    };
  };
}
```
A wrapper to add a simple flag to `hello`
```nix
# hello.nix
# This file should be called like the alacritty.nix file above
{
  hello, # Take `hello` package from pkgs
}:
{
  package = hello;
  flags.normal = [
    "--greeting='How are you?'"
  ];
}
```

You can find some examples in [nixos-config repo](https://github.com/langsjo/nixos-config/tree/master/packages/wrappers)
