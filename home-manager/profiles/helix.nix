{ lib, pkgs, ... }:

{
  programs.helix = {
    enable = true;
    package = pkgs.helix.override (old: {
      lockedGrammars = lib.filterAttrs (name: _: 
        lib.elem name [
          "bash"
          "c"
          "c-sharp"
          "cpp"
          "dockerfile"
          "dot"
          "fish"
          "fsharp"
          "git-config"
          "git-rebase"
          "gitattributes"
          "gitcommit"
          "gitignore"
          "go"
          "haskell"
          "hosts"
          "html"
          "ini"
          "java"
          "javascript"
          "jq"
          "json"
          "json5"
          "llvm"
          "llvm-mir"
          "lua"
          "make"
          "markdown"
          "markdown-inline"
          "nginx"
          "nix"
          "passwd"
          "pem"
          "proto"
          "python"
          "regex"
          "rust"
          "rust-format-args"
          "strace"
          "toml"
          "typescript"
          "typst"
          "vue"
          "xml"
          "yaml"
          "zig"
        ]) (lib.importJSON "${pkgs.path}/pkgs/by-name/he/helix/grammars.json");
    });
    defaultEditor = true;

    settings = {
      editor = {
        line-number = "relative";
        cursorline = true;
      };
    };

    languages = {
      language-server = {
        clice = {
          command = "clice";
        };
        helix-assist = {
          command = "helix-assist";
          # TODO: sops
        };
        ty = {
          command = "ty";
          args = [ "server" ];
        };
      };

      language = [
        {
          name = "cpp";
          auto-format = true;
          language-servers = [ "clice" ];
        }
        {
          name = "git-commit";
          language-servers = [ "helix-assist" ];
        }
        {
          name = "lua";
          auto-format = true;
          language-servers = [ "lua-language-server" "helix-assist" ];
        }
        {
          name = "python";
          auto-format = true;
          language-servers = [ "ty" "ruff" "helix-assist" ];
          roots = [ "pyproject.toml" ];
          formatter = {
            command = "sh";
            args = [ "-c" "ruff check --fix-only - | ruff format -" ];
          };
        }
      ];
    };
  };
}
