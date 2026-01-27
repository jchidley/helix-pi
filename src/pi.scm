;;; pi.scm - Helix integration for pi coding agent
;;; 
;;; This is a thin layer that wires up pi-core.scm to Helix.
;;; All testable logic lives in pi-core.scm.
;;;
;;; Commands:
;;;   pi-start    - Start new pi session
;;;   pi-continue - Resume previous session (cache-friendly)
;;;   pi-resume   - Picker to select session
;;;   pi-send     - Send input buffer contents
;;;   pi-abort    - Abort current operation
;;;   pi-quit     - Close session

(require-builtin steel/process)
(require "steel/result")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")
(require (only-in "helix/ext.scm" hx.block-on-task))
(require "mattwparas-helix-package/cogs/labelled-buffers.scm")
(require (only-in "mattwparas-helix-package/cogs/picker.scm" picker-selection))

;; Import core logic
(require "pi-core.scm")

(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume)

;;; ============ Constants ============

(define PI-OUTPUT "pi/output")
(define PI-INPUT "pi/input")

;;; ============ Process State ============

(define *pi-process* #f)
(define *pi-stdin* #f)
(define *pi-stdout* #f)

(define (pi-running?)
  (and *pi-process* *pi-stdin* *pi-stdout*))

;;; ============ Buffer State ============

(define *pi-output-doc-id* #f)
(define *pi-input-doc-id* #f)

;;; ============ Helix Buffer Operations ============

;; Switch to a buffer, reusing existing view if possible
(define (switch-to-doc doc-id)
  (define maybe-view-id (editor-doc-in-view? doc-id))
  (if maybe-view-id
      (editor-set-focus! maybe-view-id)
      (editor-switch! doc-id)))

(define (switch-to-output)
  (if *pi-output-doc-id*
      (switch-to-doc *pi-output-doc-id*)
      (open-labelled-buffer PI-OUTPUT)))

(define (switch-to-input)
  (if *pi-input-doc-id*
      (switch-to-doc *pi-input-doc-id*)
      (open-labelled-buffer PI-INPUT)))

;; Helix callback: append text to output buffer
(define (helix-append-output text)
  (temporarily-switch-focus
    (lambda ()
      (switch-to-output)
      (helix.static.goto_file_end)
      (helix.static.insert_string text))))

;; Helix callback: set status bar
(define (helix-set-status msg)
  (set-status! msg))

;; Initialize callbacks for pi-core
(pi-set-callbacks!
  #:append-output helix-append-output
  #:set-status helix-set-status
  #:on-unknown-event (lambda (type) 
                       (displayln (string-append "Unknown event: " (to-string type)))))

;;; ============ Buffer Management ============

(define (pi-create-buffers)
  (define output-exists (or *pi-output-doc-id* (maybe-fetch-doc-id PI-OUTPUT)))
  (define input-exists (or *pi-input-doc-id* (maybe-fetch-doc-id PI-INPUT)))
  
  (if (and output-exists input-exists)
      ;; Reuse existing buffers
      (begin
        (pi-clear-output)
        (pi-setup-window-layout))
      ;; Create new buffers with horizontal layout
      (begin
        ;; Create output buffer in a horizontal split
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-OUTPUT "]"))
        (set! *pi-output-doc-id* (editor->doc-id (editor-focus)))
        
        ;; Create input buffer below output
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-INPUT "]"))
        (set! *pi-input-doc-id* (editor->doc-id (editor-focus)))
        ;; Note: This creates 3 windows. User can close the original with C-w q
        )))

(define (pi-setup-window-layout)
  (switch-to-output)
  (helix.hsplit-new)
  (switch-to-input))

(define (pi-clear-output)
  (temporarily-switch-focus
    (lambda ()
      (switch-to-output)
      (helix.static.select_all)
      (helix.static.delete_selection))))

(define (pi-get-input)
  (define result "")
  (temporarily-switch-focus
    (lambda ()
      (switch-to-input)
      (helix.static.select_all)
      (set! result (helix.static.current-highlighted-text!))))
  result)

(define (pi-clear-input)
  (temporarily-switch-focus
    (lambda ()
      (switch-to-input)
      (helix.static.select_all)
      (helix.static.delete_selection))))

;;; ============ RPC Communication ============

(define (pi-rpc-send request)
  "Send a request hash to pi process."
  (when (pi-running?)
    (let ([json-str (value->jsexpr-string request)])
      (#%raw-write-string json-str *pi-stdin*)
      (#%raw-write-string "\n" *pi-stdin*)
      (flush-output-port *pi-stdin*))))

;;; ============ Event Loop ============

(define (pi-event-loop)
  (spawn-native-thread
    (lambda ()
      (let loop ()
        (let ([line (read-line-from-port *pi-stdout*)])
          (when line
            (let ([event (string->jsexpr line)])
              (hx.block-on-task
                (lambda ()
                  (pi-handle-event event))))
            (loop)))))))

;;; ============ Session Discovery ============

(define (get-home-dir)
  (let ([child (spawn-process (with-stdout-piped (command "printenv" '("HOME"))))])
    (when (Ok? child)
      (trim (read-port-to-string (child-stdout (unwrap-ok child)))))))

(define (pi-sessions-dir)
  (string-append (get-home-dir) "/.pi/agent/sessions"))

(define (get-latest-session-file session-dir)
  (let ([files (read-dir session-dir)])
    (let ([jsonl-files (filter (lambda (f) (ends-with? f ".jsonl")) files)])
      (if (null? jsonl-files)
          #f
          (car (sort jsonl-files string>?))))))

(define (get-cwd-latest-session)
  (let* ([cwd (current-directory)]
         [session-dir-name (path-to-session-dir-name cwd)]
         [session-dir (string-append (pi-sessions-dir) "/" session-dir-name)])
    (if (path-exists? session-dir)
        (get-latest-session-file session-dir)
        #f)))

(define (get-first-user-message session-file)
  (call-with-input-file session-file
    (lambda (port)
      (let ([messages (parse-session-file-events port)])
        (if (null? messages)
            "(empty)"
            (let ([first-text (cdar messages)])
              (if (null? first-text)
                  "(empty)"
                  (let ([text (car first-text)])
                    (if (> (string-length text) 50)
                        (string-append (substring text 0 47) "...")
                        text)))))))))

(define (list-sessions-for-cwd)
  (let* ([cwd (current-directory)]
         [session-dir-name (path-to-session-dir-name cwd)]
         [session-dir (string-append (pi-sessions-dir) "/" session-dir-name)])
    (if (path-exists? session-dir)
        (let ([files (read-dir session-dir)])
          (let ([jsonl-files (filter (lambda (f) (ends-with? f ".jsonl")) files)])
            (let ([sorted (sort jsonl-files string>?)])
              (map (lambda (f)
                     (cons (get-first-user-message f) f))
                   sorted))))
        '())))

(define (display-session-history session-file)
  (call-with-input-file session-file
    (lambda (port)
      (let ([messages (parse-session-file-events port)])
        (helix-append-output (format-session-history messages))))))

;;; ============ Commands ============

(define *pi-session-map* (hash))

;;@doc
;; Start a NEW pi coding agent session
(define (pi-start)
  (if (pi-running?)
      (set-status! "pi: already running")
      (pi-spawn-process '("--mode" "rpc"))))

;;@doc
;; Continue previous pi session (cache-friendly)
(define (pi-continue)
  (if (pi-running?)
      (set-status! "pi: already running")
      (let ([session-file (get-cwd-latest-session)])
        (pi-spawn-process '("--mode" "rpc" "--continue")
                          #:session-file session-file))))

;;@doc
;; Show picker to select and resume a session
(define (pi-resume)
  (if (pi-running?)
      (set-status! "pi: already running")
      (let ([sessions (list-sessions-for-cwd)])
        (if (null? sessions)
            (set-status! "pi: no sessions found")
            (begin
              (set! *pi-session-map*
                    (fold (lambda (pair acc)
                            (hash-insert acc (car pair) (cdr pair)))
                          (hash)
                          sessions))
              (push-component!
                (picker-selection 
                  (map car sessions)
                  (lambda (selected)
                    (let ([session-file (hash-try-get *pi-session-map* selected)])
                      (if session-file
                          (pi-spawn-process
                            (list "--mode" "rpc" "--session" session-file)
                            #:session-file session-file)
                          (set-status! "pi: session not found"))))
                  #:highlight-prefix "> ")))))))

(define (pi-spawn-process args #:session-file [session-file #f])
  (let ([result (spawn-process
                  (with-stdout-piped
                    (with-stdin-piped
                      (command "pi" args))))])
    (if (Ok? result)
        (let ([child (unwrap-ok result)])
          (set! *pi-process* child)
          (set! *pi-stdin* (child-stdin child))
          (set! *pi-stdout* (child-stdout child))
          
          (pi-create-buffers)
          (pi-event-loop)
          
          (when session-file
            (display-session-history session-file)
            (helix-append-output "---\n\n"))
          (set-status! "pi: ready"))
        (set-status! "pi: failed to start process"))))

;;@doc
;; Send the input buffer contents to pi
(define (pi-send)
  (if (not (pi-running?))
      (set-status! "pi: not running (use :pi-start)")
      (let ([text (trim (pi-get-input))])
        (if (equal? text "")
            (set-status! "pi: empty prompt")
            (begin
              (pi-rpc-send (pi-make-prompt-request text))
              (pi-clear-input)
              (set-status! "pi: sending..."))))))

;;@doc
;; Abort the current pi operation
(define (pi-abort)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-rpc-send (pi-make-abort-request))
        (set-status! "pi: abort sent"))))

;;@doc
;; Quit the pi session
(define (pi-quit)
  (when *pi-process*
    (close-output-port *pi-stdin*)
    (set! *pi-process* #f)
    (set! *pi-stdin* #f)
    (set! *pi-stdout* #f)
    (set-status! "pi: stopped (session saved)")))
