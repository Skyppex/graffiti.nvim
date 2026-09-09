{pkgs, ...}: {
  # https://devenv.sh/packages/
  packages = with pkgs; [
    stylua
    jq
    vscode-json-languageserver
    markdownlint-cli
    beautysh
    alejandra
  ];

  # https://devenv.sh/languages/
  languages.lua.enable = true;
  languages.nix.enable = true;
}
