# Steel Plugin Patterns Reference

Reusable patterns for Helix Steel plugins. Each pattern includes minimal code and references to real implementations.

**Source**: Extracted from [helix-config](https://github.com/mattwparas/helix-config) and community plugins.

## Pattern: Simple Command

The minimal pattern for a typed command.

```scheme
;; In helix.scm
(require (prefix-in helix. "helix/commands.scm"))
(require "helix/misc.scm")

(provide git-add)

;;@doc
;; Add current file to git
(define (git-add)
  (helix.run-shell-command "git" "add" (current-path)))

(define (current-path)
  (let* ([focus (editor-focus)]
         [doc-id (editor->doc-id focus)])
    (editor-document->path doc-id)))
```

## Pattern: Labelled Buffer

Create a named scratch buffer for plugin output (file tree, git status, etc).

```scheme
(require "helix/editor.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))

;; Unique identifier
(define MY-BUFFER "github.com/user/my-plugin")

;; Buffer state tracking
(define *buffer-doc-id* #f)

(define (ensure-buffer-exists)
  (unless (and *buffer-doc-id* (editor-doc-exists? *buffer-doc-id*))
    ;; Create new scratch buffer
    (helix.vsplit-new)
    (set! *buffer-doc-id* (editor->doc-id (editor-focus)))
    (set-scratch-buffer-name! *buffer-doc-id* MY-BUFFER)))

(define (write-to-buffer content)
  (ensure-buffer-exists)
  (helix.static.select_all)
  (helix.static.delete_selection)
  (helix.static.insert_string content))
```

**Used by**: file-tree.scm, git-status-picker.scm

## Pattern: Popup Picker

Show a selection list that opens files or triggers actions.

```scheme
(require "helix/misc.scm")

(provide my-picker)

(define *items* '("item1" "item2" "item3"))

;;@doc
;; Show picker with items
(define (my-picker)
  (push-component! (picker *items*)))
```

For custom behavior, use `new-component!`:

```scheme
(define (custom-picker items)
  (push-component!
    (new-component! 
      "my-picker"                    ; Unique name
      items                          ; State
      render-fn                      ; Render function
      (hash "handle_event" event-fn) ; Event handlers
    )))
```

**Used by**: recentf.scm, streal.hx

## Pattern: Custom Component (Advanced)

Full UI component with rendering and event handling.

```scheme
(require-builtin helix/components)
(require "helix/misc.scm")
(require "helix/editor.scm")

(define COMPONENT-NAME "my-component")

(define (render-component state rect frame)
  ;; state: your custom state passed to new-component!
  ;; rect: available area (use area-width, area-height, area-x, area-y)
  ;; frame: buffer to draw into
  
  (define popup-area (area 10 5 40 10))  ; x y width height
  (buffer/clear frame popup-area)
  
  ;; Draw border
  (define style (theme-scope *helix.cx* "ui.popup"))
  (block/render frame popup-area
    (make-block (theme->bg *helix.cx*) style "all" "rounded"))
  
  ;; Draw text
  (frame-set-string! frame 12 7 "Hello World" style))

(define (handle-component-event state event)
  (define char (key-event-char event))
  
  (cond
    [(key-event-escape? event) event-result/close]
    [(eqv? char #\q) event-result/close]
    [else event-result/consume]))

(define (show-component)
  (push-component!
    (new-component!
      COMPONENT-NAME
      '()                            ; Initial state
      render-component
      (hash "handle_event" handle-component-event))))
```

**Used by**: notify.hx, scooter.hx

## Pattern: Prompt Input

Get user input via the command prompt.

```scheme
(require "helix/misc.scm")

(define (helix-prompt! prompt-str callback)
  (push-component! (prompt prompt-str callback)))

;;@doc
;; Ask for filename and create it
(define (create-file)
  (helix-prompt! "New file: "
    (lambda (filename)
      (helix.open filename)
      (helix.write filename))))
```

**Used by**: file-tree.scm (create-file, create-directory)

## Pattern: Async/Delayed Execution

Schedule work without blocking the UI.

```scheme
(require "helix/misc.scm")

;; Run callback after current execution completes
(enqueue-thread-local-callback
  (lambda ()
    (set-status! "Delayed message")))

;; Run callback after delay (milliseconds)
(enqueue-thread-local-callback-with-delay 2000
  (lambda ()
    (set-status! "2 seconds later")))
```

For long-running tasks, use threads:

```scheme
(require-builtin steel/time)
(require "helix/ext.scm")

(spawn-native-thread
  (lambda ()
    ;; Heavy computation here...
    (hx.block-on-task  ; Acquire helix context on main thread
      (lambda ()
        (set-status! "Task complete")))))
```

**Used by**: notify.hx (auto-dismiss), recentf.scm (periodic save)

## Pattern: File Persistence

Save plugin state between sessions.

```scheme
(define CONFIG-FILE ".helix/my-plugin-state.txt")

(define (read-state)
  (if (path-exists? CONFIG-FILE)
      (call-with-input-file CONFIG-FILE
        (lambda (f) (read! (read-port-to-string f))))
      '()))  ; Default state

(define (write-state state)
  (unless (path-exists? ".helix")
    (create-directory! ".helix"))
  (call-with-output-file CONFIG-FILE
    (lambda (f)
      (for-each (lambda (item)
                  (write-line! f item))
                state))))
```

**Used by**: recentf.scm, streal.hx

## Pattern: Buffer-Specific Keybindings

Apply different keybindings based on buffer type.

```scheme
;; In init.scm
(require "cogs/keymaps.scm")

(define my-buffer-keybindings
  (hash "normal"
        (hash "tab" ':my-action
              "q" ':close-buffer)))

(define standard (deep-copy-global-keybindings))
(merge-keybindings standard my-buffer-keybindings)

(set-global-buffer-or-extension-keymap
  (hash "my-buffer-name" standard))
```

**Used by**: file-tree.scm (FILE-TREE-KEYBINDINGS)

## Pattern: LSP Integration

Send commands to language servers.

```scheme
(require "helix/misc.scm")

(define (send-lsp-request)
  (send-lsp-command
    "rust-analyzer"                    ; LSP name
    "rust-analyzer/viewCrateGraph"     ; Method
    (hash "full" #f)                   ; Params
    (lambda (result)                   ; Callback
      (displayln result))))
```

## Pattern: Process Communication (for pi RPC)

Spawn external processes with piped I/O.

```scheme
(require-builtin steel/process)
(require "steel/result")

(define (start-process)
  (define child 
    (unwrap-ok 
      (spawn-process 
        (with-stdout-piped 
          (with-stdin-piped 
            (command "pi" '("--mode" "rpc" "--no-session")))))))
  
  (define stdin (child-stdin child))
  (define stdout (child-stdout child))
  
  ;; Send request
  (write-line! stdin "{\"type\": \"get_state\"}")
  
  ;; Read response
  (read-line-from-port stdout))
```

This is the foundation for helix-pi integration with the pi coding agent.
