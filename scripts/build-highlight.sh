#!/bin/sh
# Rebuilds Packages/UncialCore/Sources/UncialCore/Resources/highlight.min.js (and HIGHLIGHT-LICENSE):
# highlight.js core with the grammars listed in LANGUAGES, the highlightjs-cobol grammar, a small
# Scratch (scratchblocks) grammar and extra fence aliases, bundled by esbuild into one IIFE that
# leaves `hljs` on globalThis, which is what CodeHighlighter reads in its JavaScriptCore context.
#
# Usage: scripts/build-highlight.sh   (needs node and npm; the pinned packages go into a temp dir)
set -eu

HIGHLIGHT_VERSION=11.12.0
COBOL_VERSION=0.3.3
ESBUILD_VERSION=0.28.2

# highlight.js grammar modules, one per fence language. The languages of
# https://dev.to/johnrushx/38-programming-languages-which-is-best-584f come first (Scratch and COBOL
# are added below), then formats that show up in READMEs. `shell` is registered as `console` (a
# session with prompts, like GitHub) so that `shell` can mean bash.
LANGUAGES="basic python javascript java c cpp sql php swift kotlin r go dart csharp vbnet perl ruby scala
objectivec x86asm armasm fortran lua rust julia typescript bash shell groovy fsharp elm elixir haskell
prolog matlab delphi clojure
json yaml xml css markdown diff makefile dockerfile ini powershell plaintext"

root=$(cd "$(dirname "$0")/.." && pwd)
resources="$root/Packages/UncialCore/Sources/UncialCore/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

npm install --silent --no-audit --no-fund "highlight.js@$HIGHLIGHT_VERSION" "highlightjs-cobol@$COBOL_VERSION" "esbuild@$ESBUILD_VERSION"

{
  echo "import hljs from 'highlight.js/lib/core';"
  echo "import cobolBase from 'highlightjs-cobol';"
  for language in $LANGUAGES; do
    echo "import $(echo "$language" | tr -d -) from 'highlight.js/lib/languages/$language';"
  done
  cat <<'JS'

// highlightjs-cobol is written for fixed-form sources: it paints the first six columns of every
// line (the sequence area) as a comment, which mangles the free-form snippets READMEs carry, and it
// knows no `*>` comment. Its keyword list (the 2022 standard) stays; the lexical rules are ours.
function cobol(hljs) {
  const base = cobolBase(hljs);
  return {
    name: 'COBOL',
    aliases: ['cobol', 'cbl', 'cob'],
    case_insensitive: true,
    keywords: base.keywords,
    contains: [
      { scope: 'comment', begin: /^[ 0-9]{6}[*\/]/, end: /$/ },
      { scope: 'comment', begin: /\*>/, end: /$/ },
      { scope: 'meta', begin: />>/, end: /$/ },
      { scope: 'type', begin: /(?<=\b(?:PIC|PICTURE)\s+(?:IS\s+)?)[-+$*9SVXZAB().,\/]+/ },
      { scope: 'string', begin: /"/, end: /"/ },
      { scope: 'string', begin: /'/, end: /'/ },
      { scope: 'number', begin: /\b\d+(?:[.,]\d+)*\b/ },
    ],
  };
}

// Scratch has no text syntax of its own; this is the scratchblocks notation: control words as
// keywords, (reporters), <booleans>, [text inputs] and `:: category` annotations.
function scratch(hljs) {
  const NUMBER = { scope: 'number', begin: /\(\s*-?\d+(?:\.\d+)?\s*\)/ };
  const STRING = { scope: 'string', begin: /\[/, end: /\]/ };
  const REPORTER = { scope: 'variable', begin: /\(/, end: /\)/, contains: [NUMBER, STRING, 'self'] };
  const BOOLEAN = { scope: 'built_in', begin: /</, end: />(?!\s*[(<\[])/, contains: [NUMBER, STRING, REPORTER, 'self'] };
  return {
    name: 'Scratch',
    aliases: ['scratchblocks'],
    case_insensitive: true,
    keywords: {
      $pattern: /[a-z]+/,
      keyword: 'when flag clicked forever repeat until if then else end wait define stop broadcast and not or',
    },
    contains: [hljs.COMMENT(/\/\//, /$/), { scope: 'meta', begin: /::/, end: /$/ }, NUMBER, STRING, BOOLEAN, REPORTER],
  };
}

JS
  for language in $LANGUAGES; do
    name=$language
    [ "$language" = shell ] && name=console
    echo "hljs.registerLanguage('$name', $(echo "$language" | tr -d -));"
  done
  cat <<'JS'
hljs.registerLanguage('cobol', cobol);
hljs.registerLanguage('scratch', scratch);

// Fence names beyond the grammars' own aliases, the way GitHub's linguist resolves them.
const aliases = {
  bash: ['shell', 'shellscript', 'shell-script'],
  x86asm: ['asm', 'assembly', 'nasm', 'masm', 'x86'],
  vbnet: ['visualbasic', 'visual-basic', 'vba'],
  objectivec: ['objective-c', 'obj-c'],
  delphi: ['objectpascal', 'object-pascal'],
  basic: ['qbasic'],
  sql: ['mysql', 'postgresql', 'postgres', 'sqlite', 'tsql', 'plsql'],
  cobol: ['cbl', 'cob'],
  julia: ['jl'],
  r: ['rscript'],
  matlab: ['octave'],
  fortran: ['f', 'f77', 'f03', 'f08'],
  markdown: ['mdown', 'mkdn'],
  plaintext: ['plain', 'none'],
};
for (const [language, names] of Object.entries(aliases)) {
  hljs.registerAliases(names, { languageName: language });
}

globalThis.hljs = hljs;
JS
} > entry.js

banner="/* highlight.js $HIGHLIGHT_VERSION (BSD-3-Clause) with highlightjs-cobol $COBOL_VERSION (Apache-2.0); grammars: $(echo $LANGUAGES) cobol scratch. Built by scripts/build-highlight.sh; notices in HIGHLIGHT-LICENSE. */"
npx esbuild entry.js --bundle --minify --format=iife --target=safari17 --banner:js="$banner" --outfile="$resources/highlight.min.js"

{
  echo "highlight.js $HIGHLIGHT_VERSION — https://github.com/highlightjs/highlight.js"
  echo
  cat node_modules/highlight.js/LICENSE
  echo
  echo "----------------------------------------------------------------------"
  echo
  echo "highlightjs-cobol $COBOL_VERSION — https://github.com/otterkit/highlightjs-cobol"
  echo
  cat node_modules/highlightjs-cobol/LICENSE
} > "$resources/HIGHLIGHT-LICENSE"

ls -l "$resources/highlight.min.js" "$resources/HIGHLIGHT-LICENSE"
