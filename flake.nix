{
  description = "Flake templates";

  outputs =
    { self, ... }:
    {
      templates = {
        python = {
          path = ./templates/python;
          description = "Master — python (impure-uv default, pure-nix alt) ± rust accelerator + image";
        };

        rust = {
          path = ./templates/rust;
          description = "Pure rust crane workspace with optional container image";
        };

        rust-python = {
          path = ./templates/rust-python;
          description = "Rust binary embedding pure-nix python via pyo3 (wizard pattern)";
        };

        default = self.templates.python;
      };
    };
}
