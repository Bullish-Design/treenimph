{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/basics/
  env = {
    GREET = "devenv";
  };

  # https://devenv.sh/packages/
  packages = [
    pkgs.git
    pkgs.nim
    pkgs.nodejs
    pkgs.tree-sitter
  ];

  # https://devenv.sh/languages/
  # languages.rust.enable = true;
  languages = {};

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo hello from $GREET
  '';

  scripts.ts-generate.exec = ''
    set -euo pipefail
    if [ $# -lt 1 ]; then
      echo "Usage: ts-generate <exported-tree-sitter-package-dir>" >&2
      exit 2
    fi
    cd "$1"
    exec tree-sitter generate
  '';

  enterShell = ''
    hello
    git --version
    nim --version | head -n 1
    tree-sitter --version
  '';

  # https://devenv.sh/tasks/
  # tasks = {
  #   "myproj:setup".exec = "mytool build";
  #   "devenv:enterShell".after = [ "myproj:setup" ];
  # };

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
    nim --version >/dev/null
    tree-sitter --version >/dev/null
  '';

  # https://devenv.sh/pre-commit-hooks/
  # pre-commit.hooks.shellcheck.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}
