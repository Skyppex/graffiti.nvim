{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  # https://devenv.sh/packages/
  packages = with pkgs; [
    stylua
    jq
    vscode-json-languageserver
    markdownlint-cli
    beautysh
    nixd
    alejandra
  ];

  # https://devenv.sh/languages/
  languages.lua.enable = true;
}
