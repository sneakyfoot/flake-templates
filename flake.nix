{
  description = "Flake templates";

  outputs = { self, ... }: {
    templates = {
      rust = {
        path = ./templates/rust;
        description = "Rust flake for cargo etc";
      };

      python = {
        path = ./templates/python;
        description = "Python flake for impure uv apps";
      };

      defaultTemplate = self.templates.python;
    };
  };
}
