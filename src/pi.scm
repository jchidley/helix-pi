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
;;;   pi-recover  - Force reset state (emergency)

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

(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume pi-recover)

;;; ============ Constants ============

(define PI-OUTPUT "pi/output")
(define PI-INPUT "pi/input")

;;; ============ State ============
;;; Single mutable struct holds ALL state for the current pi session

(struct pi-state
  (session      ; pi-session from pi-core (handles events, RPC)
   process      ; child process handle
   stdin        ; input port to process
   stdout       ; output port from process
   stderr       ; error port from process
   output-doc   ; helix document id for output buffer
   input-doc    ; helix document id for input buffer
   ) #:mutable)

;; The one and only global - holds current session state or #f
(define *pi* #f)

(define (pi-running?)
  (and *pi* (pi-state-process *pi*)))

(define (current-session)
  "Get current pi-session or #f."
  (and *pi* (pi-state-session *pi*)))

(define (pi-cleanup!)
  "Clean up any existing session. Safe to call multiple times."
  (when *pi*
    ;; Close stdin to signal process to exit
    (let ([stdin (pi-state-stdin *pi*)])
      (when stdin
        (with-handler (lambda (e) #f)  ; ignore errors on close
          (close-output-port stdin))))
    ;; Clear state - event loops will detect this and exit
    (set! *pi* #f)))

;;; ============ Helix Buffer Operations ============

(define (switch-to-doc doc-id)
  (define maybe-view-id (editor-doc-in-view? doc-id))
  (if maybe-view-id
      (editor-set-focus! maybe-view-id)
      (editor-switch! doc-id)))

(define (switch-to-output)
  (if (and *pi* (pi-state-output-doc *pi*))
      (switch-to-doc (pi-state-output-doc *pi*))
      (open-labelled-buffer PI-OUTPUT)))

(define (switch-to-input)
  (if (and *pi* (pi-state-input-doc *pi*))
      (switch-to-doc (pi-state-input-doc *pi*))
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

;;; ============ Buffer Management ============

(define (pi-create-buffers)
  (define output-exists (or (and *pi* (pi-state-output-doc *pi*))
                            (maybe-fetch-doc-id PI-OUTPUT)))
  (define input-exists (or (and *pi* (pi-state-input-doc *pi*))
                           (maybe-fetch-doc-id PI-INPUT)))
  
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
        (when *pi*
          (set-pi-state-output-doc! *pi* (editor->doc-id (editor-focus))))
        
        ;; Create input buffer below output
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-INPUT "]"))
        (when *pi*
          (set-pi-state-input-doc! *pi* (editor->doc-id (editor-focus)))))))

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
  "Send a request hash to pi process. Returns #t on success, #f on failure."
  (if (not (pi-running?))
      #f
      (with-handler
        (lambda (err)
          ;; Write failed - process likely dead
          (when *pi*
            (pi-session-reset! (pi-state-session *pi*)))
          (set! *pi* #f)
          (set-status! "pi: send failed (process died)")
          #f)
        (let ([json-str (value->jsexpr-string request)]
              [stdin (pi-state-stdin *pi*)])
          (#%raw-write-string json-str stdin)
          (#%raw-write-string "\n" stdin)
          (flush-output-port stdin)
          #t))))

;;; ============ Event Loop ============

(define (pi-event-loop)
  (let ([stdout (pi-state-stdout *pi*)]
        [session (pi-state-session *pi*)]
        [my-pi *pi*])  ; Capture reference to detect if we're still active
    (spawn-native-thread
      (lambda ()
        (let loop ()
          ;; Check if we're still the active session
          (when (eq? *pi* my-pi)
            (let ([line (read-line-from-port stdout)])
              (if (string? line)
                  (let ([parse-result (try-parse-json line)])
                    (if parse-result
                        (begin
                          (hx.block-on-task
                            (lambda ()
                              (when (eq? *pi* my-pi)
                                (safe-handle-event session parse-result))))
                          (loop))
                        ;; JSON parse failed - log and continue
                        (begin
                          (hx.block-on-task
                            (lambda ()
                              (displayln (string-append "pi: failed to parse: " (to-string line)))))
                          (loop))))
                  ;; EOF - process terminated
                  (hx.block-on-task
                    (lambda ()
                      ;; Only update state if we're still the active session
                      (when (eq? *pi* my-pi)
                        (pi-session-reset! session)
                        (set! *pi* #f)
                        (set-status! "pi: process ended")))))))))))

(define (try-parse-json str)
  "Try to parse JSON, return #f on failure."
  (with-handler
    (lambda (err) #f)
    (string->jsexpr str)))

(define (safe-handle-event session event)
  "Handle event with error recovery."
  (with-handler
    (lambda (err)
      (displayln (string-append "pi: event handler error: " (to-string err)))
      (when (pi-session? session)
        (pi-session-reset! session))
      (set-status! "pi: error (see log)"))
    (when (pi-session? session)
      (pi-handle-event session event))))

(define (pi-stderr-loop)
  "Monitor stderr and display any output as errors."
  (let ([stderr (pi-state-stderr *pi*)]
        [my-pi *pi*])  ; Capture reference to detect if we're still active
    (spawn-native-thread
      (lambda ()
        (let loop ()
          ;; Check if we're still the active session
          (when (eq? *pi* my-pi)
            (let ([line (read-line-from-port stderr)])
              ;; Check for string (not eof)
              (when (string? line)
                (hx.block-on-task
                  (lambda ()
                    (when (eq? *pi* my-pi)
                      (helix-append-output (string-append "\n**stderr**: " line "\n")))))
                (loop)))))))))

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

(define *pi-session-map* (hash))  ; For picker - maps display text to filename

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
  ;; Ensure any previous session is cleaned up first (singleton)
  (pi-cleanup!)
  
  ;; Create fresh session with callbacks
  (let ([session (make-pi-session
                   #:append-output helix-append-output
                   #:set-status helix-set-status
                   #:on-unknown-event (lambda (type)
                                        (displayln (string-append "Unknown event: " (to-string type)))))])
    
    (let ([result (spawn-process
                    (with-stdout-piped
                      (with-stderr-piped
                        (with-stdin-piped
                          (command "pi" args)))))])
      (if (Ok? result)
          (let ([child (unwrap-ok result)])
            ;; Create state struct with all session data
            (set! *pi* (pi-state session
                                 child
                                 (child-stdin child)
                                 (child-stdout child)
                                 (child-stderr child)
                                 #f   ; output-doc - set by pi-create-buffers
                                 #f)) ; input-doc
            
            (pi-create-buffers)
            (pi-event-loop)
            (pi-stderr-loop)
            
            (when session-file
              (display-session-history session-file)
              (helix-append-output "---\n\n"))
            (set-status! "pi: ready"))
          (set-status! "pi: failed to start process"))))))

;;@doc
;; Send the input buffer contents to pi
;; If streaming, queues as follow-up instead
(define (pi-send)
  (cond
    [(not (pi-running?))
     (set-status! "pi: not running (use :pi-start)")]
    [(pi-session-streaming? (current-session))
     ;; Queue as follow-up instead of error
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (when (pi-rpc-send (pi-make-follow-up-request (current-session) text))
             (pi-clear-input)
             (set-status! "pi: queued follow-up"))))]
    [else
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (when (pi-rpc-send (pi-make-prompt-request (current-session) text))
             (pi-clear-input)
             (set-status! "pi: sending..."))))]))

;;@doc
;; Abort the current pi operation
(define (pi-abort)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-rpc-send (pi-make-abort-request (current-session)))
        (set-status! "pi: abort sent"))))

;;@doc
;; Quit the pi session
(define (pi-quit)
  (if (not *pi*)
      (set-status! "pi: not running")
      (begin
        (pi-cleanup!)
        (set-status! "pi: stopped (session saved)"))))

;;@doc
;; Force reset pi state (use if stuck due to process crash)
(define (pi-recover)
  (pi-cleanup!)
  (set-status! "pi: recovered (use :pi-start to restart)"))
