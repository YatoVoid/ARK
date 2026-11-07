# HolyC for VS Code

Syntax highlighting and a few snippets for HolyC files (`.HC`, `.HH`), written for this repo. No code runs: it's a TextMate grammar, a language configuration and a snippets file.

HolyC files get their own language id, so C tools (clangd, cpptools) leave them alone and don't flag HolyC syntax as C errors.

## Install

```sh
cd tools/vscode-holyc
npx --yes @vscode/vsce package --allow-missing-repository -o holyc.vsix
code --install-extension holyc.vsix
```

Then reload the VS Code window. Completion is VS Code's built-in word completion plus the snippets (`main`, `class`, `extern`, `print`, `for`). There's no language server, so no go-to-definition across files.
