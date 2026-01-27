# Tutorial: Your First Steel Plugin for Helix

Build a word counter plugin to learn the basics of Steel plugin development.

## Before You Start

- Helix with Steel support: `~/git/helix/target/release/hx`
- Steel CLI: `steel --version`
- Basic familiarity with Lisp/Scheme syntax (parentheses everywhere!)

## Step 1: Test in Steel REPL

Start the REPL:

```bash
steel
```

You should see:

```
     _____ __            __
    / ___// /____  ___  / /          Version 0.7.0
    \__ \/ __/ _ \/ _ \/ /           https://github.com/mattwparas/steel
   ___/ / /_/  __/  __/ /            :? for help
  /____/\__/\___/\___/_/

λ >
```

Test basic Scheme:

```scheme
λ > (+ 1 2 3)
=> 6

λ > (define (square x) (* x x))
λ > (square 5)
=> 25
```

## Step 2: Learn String Functions

Try splitting a string:

```scheme
λ > (split-whitespace "hello world test")
=> '("hello" "world" "test")

λ > (length (split-whitespace "hello world test"))
=> 3
```

## Step 3: Create Word Count Function

```scheme
λ > (define (count-words text)
      (length (split-whitespace text)))
λ > (count-words "the quick brown fox")
=> 4
```

Exit the REPL with Ctrl+D.

## Step 4: Add to Helix Config

Edit `~/.config/helix/helix.scm` and add:

```scheme
;; Requires at top of file (if not already present)
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/misc.scm")

;; Export the function
(provide word-count)

;;@doc
;; Count words in current selection and show in status bar
(define (word-count)
  (let* ([text (helix.static.current-highlighted-text!)]
         [count (length (split-whitespace text))])
    (set-status! (string-append "Words: " (number->string count)))))
```

## Step 5: Test in Helix

1. Start Helix: `~/git/helix/target/release/hx somefile.txt`
2. Select some text (visual mode: `v` then move)
3. Type `:word-count`
4. See the count in the status bar

## Step 6: Debug with :evalp

If something doesn't work:

1. Type `:evalp`
2. Enter: `(split-whitespace "test string")`
3. Result appears in status bar

Or use `:open-debug-window` to see `displayln` output.

## What You Learned

- Steel REPL for testing pure Scheme
- `helix.scm` for defining exportable commands
- `(provide name)` to export functions as commands
- `;;@doc` comments appear in command palette
- `helix.static.*` APIs for editor interaction
- `set-status!` for user feedback

## Next Steps

- [How-to: Debug Steel Plugins](howto-debug.md)
- [Reference: Helix Steel APIs](reference.md)
- [Patterns: Common Plugin Architectures](patterns.md)
