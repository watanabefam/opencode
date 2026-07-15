# Workspace Convention

<WORKSPACE_CONVENTION>
  Convention for organizing project outputs into a shared workspace
  with per-project subfolders containing both inputs and generated artifacts.

  ## Layout

  <LAYOUT>
    ```
    audiobook-maker/                # Generator repo (unchanged)
    ../audiobooks/                  # Workspace directory (plural category name)
      <project-name>/               # One subfolder per project
        input/                      # Source materials
        <project-name>.m4b          # Generated output at project root
        chapter_001.wav
    ```
  </LAYOUT>

  ## Rules

  <PREFLIGHT>
    Before generating, verify `../<workspace>/<project>/` exists.
    If missing: tell the user to create it, then stop.
  </PREFLIGHT>

  <INPUT_HANDLING>
    - Always check the `input/` subfolder before generating
    - List existing contents so the user knows what's already there
    - Always prompt: "Are there any source files to add?" even if `input/` is not empty
    - Copy user-provided files into `input/` for self-containment
  </INPUT_HANDLING>

  <OUTPUT_CONVENTION>
    - Source code lives in the generator repo (unchanged)
    - Source materials go in `../<workspace>/<project>/input/`
    - Generated artifacts go to `../<workspace>/<project>/` (project root)
    - Never write generated files into the source repo
  </OUTPUT_CONVENTION>

</WORKSPACE_CONVENTION>
