# system-theme.hx

system-theme.hx is a theme switcher plugin for [Helix](https://github.com/helix-editor/helix/) that automatically adapts to your system's appearance (dark/light mode).

## Usage

Add the following to `init.scm` in your Helix config directory:

```scheme
(require "system-theme-hx/system-theme.scm")
(auto-theme "tokyonight_moon" "github_light")
```

This plugin provides the `auto-theme` function that automatically switches between dark and light themes based on system preference.

### Examples

```scheme
;; Gruvbox variants
(auto-theme "gruvbox_dark_hard" "gruvbox_light_hard")

;; Catppuccin variants
(auto-theme "catppuccin_mocha" "catppuccin_latte")
```

## Installation

Follow the instructions [here](https://github.com/mattwparas/helix/blob/steel-event-system/STEEL.md) to install Helix on the plugin branch.

Then, install the plugin with one of the installation methods below.

### Using Forge

Forge is the Steel package manager, and will have been installed in the previous step. Run the following:

```sh
forge pkg install --git https://github.com/j03-dev/system-theme.hx.git
```

### Building from source

1. Clone and `cd` into this repo and run `cargo steel-lib`
1. Add `(require "<path>/system-theme.hx/system-theme.scm")` to `init.scm` in your Helix config (where `<path>` is the absolute path of the folder containing the system-theme.hx repo)
