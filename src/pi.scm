;;; pi.scm - Helix integration for pi coding agent
;;;
;;; THREADING MODEL:
;;; ================
;;; Worker threads (stdout/stderr readers) are PURE PRODUCERS:
;;;   - They only read from pipes and send messages to a channel
;;;   - They NEVER read or write any shared state
;;;   - They NEVER call Helix APIs directly
;;;
;;; Main thread (Helix) is the SOLE CONSUMER:
;;;   - All state mutations happen here
;;;   - All Helix API calls happen here
;;;   - Polls channel via timer callback
;;;
;;; Communication: worker -> main via channel (mpsc pattern)
;;; Shutdown: main sets atomic flag, workers check it

(require-builtin steel/process)
(require-builtin steel/threads)
(require-builtin steel/time)
(require-builtin helix/components)
(require "steel/result")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")
(require (only-in "helix/ext.scm" hx.block-on-task))
(require "mattwparas-helix-package/cogs/labelled-buffers.scm")
(require "mattwparas-helix-package/cogs/picker.scm")

;; Import core logic
(require "pi-core.scm")

;;; ============ Constants ============
(define PI-OUTPUT "pi/output")
(define PI-INPUT "pi/input")
(define POLL-INTERVAL-MS 50)

;;; ============ Message Types ============
;;; Messages sent from worker threads to main thread via channel
;;; All messages are simple lists: (type . data)

(define (make-stdout-msg line) (cons 'stdout line))
(define (make-stderr-msg line) (cons 'stderr line))
(define (make-stdout-eof-msg) (cons 'stdout-eof #f))
(define (make-stderr-eof-msg) (cons 'stderr-eof #f))

(define (msg-type msg) (car msg))
(define (msg-data msg) (cdr msg))

;;; ============ Process State ============
;;; Immutable struct - replaced atomically, never mutated in place

(struct pi-process
  (child           ; process handle
   stdin           ; output port (we write to it)
   session-id      ; unique ID for this session
   event-channel   ; channel receiver for worker -> main messages
   shutdown-flag)) ; mutable box: #t when workers should stop

(define (make-shutdown-flag) (box #f))
(define (shutdown-flag-set! flag) (set-box! flag #t))
(define (shutdown-flag-set? flag) (unbox flag))

;;; ============ UI State ============
;;; Separate from process state - survives process restart

(struct pi-ui
  (output-doc   ; doc-id for output buffer
   input-doc))  ; doc-id for input buffer

;;; ============ Global State ============
;;; Two globals, clearly separated:
;;;   *pi-process* - process/IPC state (or #f if not running)
;;;   *pi-ui*      - UI state (persists across restarts)
;;;   *pi-session* - core session state (streaming?, pending requests, etc.)

(define *pi-process* #f)
(define *pi-ui* #f)
(define *pi-session* #f)

;;; ============ State Predicates ============

(define (pi-running?)
  (and *pi-process* #t))

(define (pi-get-session)
  *pi-session*)

;;; ============ Worker Threads ============
;;; These are pure producers - they only:
;;;   1. Read from a pipe (blocking)
;;;   2. Send to a channel
;;;   3. Check shutdown flag
;;; They NEVER touch *pi-process*, *pi-session*, or call Helix APIs

(define (spawn-stdout-reader stdout sender shutdown-flag)
  "Spawn thread that reads stdout and sends messages to channel."
  (spawn-native-thread
    (lambda ()
      (let loop ()
        (if (shutdown-flag-set? shutdown-flag)
            'done
            (let ([line (read-line-from-port stdout)])
              (if (string? line)
                  (begin
                    (channel/send sender (make-stdout-msg line))
                    (loop))
                  ;; EOF
                  (channel/send sender (make-stdout-eof-msg)))))))))

(define (spawn-stderr-reader stderr sender shutdown-flag)
  "Spawn thread that reads stderr and sends messages to channel."
  (spawn-native-thread
    (lambda ()
      (let loop ()
        (if (shutdown-flag-set? shutdown-flag)
            'done
            (let ([line (read-line-from-port stderr)])
              (if (string? line)
                  (begin
                    (channel/send sender (make-stderr-msg line))
                    (loop))
                  ;; EOF
                  (channel/send sender (make-stderr-eof-msg)))))))))

;;; ============ Main Thread: Channel Consumer ============

(define (process-pending-messages)
  "Process all pending messages from worker threads. Called on main thread only."
  (when *pi-process*
    (let ([receiver (pi-process-event-channel *pi-process*)])
      (let loop ()
        (let ([msg (channel/try-recv receiver)])
          (unless (empty-channel-object? msg)
            (handle-worker-message msg)
            (loop)))))))

(define (handle-worker-message msg)
  "Handle a single message from a worker thread. Main thread only."
  (let ([type (msg-type msg)]
        [data (msg-data msg)])
    (cond
      [(eq? type 'stdout)
       (handle-stdout-line data)]
      [(eq? type 'stderr)
       (handle-stderr-line data)]
      [(eq? type 'stdout-eof)
       (handle-process-exit)]
      [(eq? type 'stderr-eof)
       ;; Ignore stderr EOF - stdout EOF is authoritative
       #f]
      [else
       (displayln (string-append "pi: unknown message type: " (to-string type)))])))

(define (handle-stdout-line line)
  "Handle a line of JSON from pi stdout. Main thread only."
  (let ([event (try-parse-json line)])
    (if event
        (when *pi-session*
          (safe-handle-event *pi-session* event))
        (displayln (string-append "pi: failed to parse: " line)))))

(define (handle-stderr-line line)
  "Handle a line from pi stderr. Main thread only."
  (helix-append-output (string-append "\n**stderr**: " line "\n")))

(define (handle-process-exit)
  "Handle pi process termination. Main thread only."
  (when *pi-session*
    (pi-session-reset! *pi-session*))
  (pi-cleanup!)
  (set-status! "pi: process ended"))

(define (try-parse-json str)
  (with-handler
    (lambda (err) #f)
    (string->jsexpr str)))

(define (safe-handle-event session event)
  (with-handler
    (lambda (err)
      (displayln (string-append "pi: event handler error: " (to-string err)))
      (pi-session-reset! session)
      (set-status! "pi: error (see log)"))
    (pi-handle-event session event)))

;;; ============ Polling Timer ============
;;; Uses Helix's callback mechanism to poll the channel periodically
;;;
;;; Design: We use enqueue-thread-local-callback-with-delay to schedule
;;; periodic polling. Each poll iteration:
;;;   1. Processes all pending messages from the channel
;;;   2. Reschedules itself if the process is still running
;;;
;;; The poll timer is self-terminating: it stops when *pi-process* becomes #f

(define (start-poll-timer)
  "Start the polling loop. Safe to call multiple times."
  (when *pi-process*
    (schedule-next-poll)))

(define (schedule-next-poll)
  "Schedule the next poll iteration after POLL-INTERVAL-MS."
  (enqueue-thread-local-callback-with-delay
    POLL-INTERVAL-MS
    (lambda ()
      ;; Only continue if process is still running
      (when *pi-process*
        (process-pending-messages)
        ;; Reschedule for next iteration
        (schedule-next-poll)))))

;;; ============ Helix Buffer Operations ============

(define (switch-to-doc doc-id)
  (define maybe-view-id (editor-doc-in-view? doc-id))
  (if maybe-view-id
      (editor-set-focus! maybe-view-id)
      (editor-switch! doc-id)))

(define (switch-to-output)
  (if (and *pi-ui* (pi-ui-output-doc *pi-ui*))
      (switch-to-doc (pi-ui-output-doc *pi-ui*))
      (open-labelled-buffer PI-OUTPUT)))

(define (switch-to-input)
  (if (and *pi-ui* (pi-ui-input-doc *pi-ui*))
      (switch-to-doc (pi-ui-input-doc *pi-ui*))
      (open-labelled-buffer PI-INPUT)))

(define (helix-append-output text)
  (temporarily-switch-focus
    (lambda ()
      (switch-to-output)
      (helix.static.goto_file_end)
      (helix.static.insert_string text))))

(define (helix-set-status msg)
  (set-status! msg))

;;; ============ Buffer Management ============

(define (pi-create-buffers)
  (define output-exists (or (and *pi-ui* (pi-ui-output-doc *pi-ui*))
                            (maybe-fetch-doc-id PI-OUTPUT)))
  (define input-exists (or (and *pi-ui* (pi-ui-input-doc *pi-ui*))
                           (maybe-fetch-doc-id PI-INPUT)))
  
  (if (and output-exists input-exists)
      (begin
        (pi-clear-output)
        (pi-setup-window-layout))
      (let ([output-doc #f]
            [input-doc #f])
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-OUTPUT "]"))
        (helix.set-language "markdown")
        (set! output-doc (editor->doc-id (editor-focus)))
        
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-INPUT "]"))
        (helix.set-language "markdown")
        (set! input-doc (editor->doc-id (editor-focus)))
        
        (set! *pi-ui* (pi-ui output-doc input-doc)))))

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

;;; ============ Process Lifecycle ============

(define (pi-cleanup!)
  "Clean up process state. Main thread only."
  (when *pi-process*
    ;; Signal workers to stop FIRST (before closing ports)
    (shutdown-flag-set! (pi-process-shutdown-flag *pi-process*))
    ;; Close stdin (this will cause pi to exit gracefully)
    (with-handler (lambda (e) #f)
      (close-output-port (pi-process-stdin *pi-process*)))
    ;; Clear process state - this also stops the poll timer
    ;; (poll timer checks *pi-process* and self-terminates)
    (set! *pi-process* #f)))

(define (pi-spawn-process args #:on-ready [on-ready #f])
  "Spawn pi process and set up communication. Main thread only.
   Optional on-ready callback is invoked after process is running."
  ;; Clean up any existing process first
  (pi-cleanup!)
  
  ;; Create fresh session
  ;; Note: #:send callback uses pi-rpc-send which references *pi-process*,
  ;; so this works because the session is created before spawning but the
  ;; callback isn't invoked until after the process is running.
  (set! *pi-session* (make-pi-session
                       #:append-output helix-append-output
                       #:set-status helix-set-status
                       #:on-unknown-event (lambda (type)
                                            (displayln (string-append "Unknown event: " (to-string type))))
                       #:send (lambda (req) (pi-rpc-send req))))
  
  ;; Spawn process
  (let ([result (spawn-process
                  (with-stdout-piped
                    (with-stderr-piped
                      (with-stdin-piped
                        (command "pi" args)))))])
    (if (Ok? result)
        (let* ([child (unwrap-ok result)]
               [channels (channels/new)]
               [sender (channels-sender channels)]
               [receiver (channels-receiver channels)]
               [shutdown-flag (make-shutdown-flag)]
               [session-id (current-inexact-milliseconds)])
          
          ;; Create process state
          ;; IMPORTANT: child-stdin/stdout/stderr can only be called ONCE per process!
          ;; They use .take() internally which consumes the handle.
          ;; We capture them here and pass to struct/worker threads.
          (set! *pi-process* (pi-process child
                                         (child-stdin child)
                                         session-id
                                         receiver
                                         shutdown-flag))
          
          ;; Create/setup buffers
          (pi-create-buffers)
          
          ;; Spawn worker threads (they only send to channel, never touch state)
          (spawn-stdout-reader (child-stdout child) sender shutdown-flag)
          (spawn-stderr-reader (child-stderr child) sender shutdown-flag)
          
          ;; Start polling for messages
          (start-poll-timer)
          
          ;; Call on-ready callback if provided
          (when on-ready (on-ready))
          
          (set-status! "pi: ready"))
        (set-status! "pi: failed to start process"))))

;;; ============ RPC Communication ============

(define (pi-rpc-send request)
  "Send RPC request to pi. Main thread only."
  (if (not (pi-running?))
      #f
      (with-handler
        (lambda (err)
          (when *pi-session*
            (pi-session-reset! *pi-session*))
          (pi-cleanup!)
          (set-status! "pi: send failed (process died)")
          #f)
        (let ([json-str (value->jsexpr-string request)]
              [stdin (pi-process-stdin *pi-process*)])
          (#%raw-write-string json-str stdin)
          (#%raw-write-string "\n" stdin)
          (flush-output-port stdin)
          #t))))

;;; ============ Commands ============

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
      (pi-spawn-process '("--mode" "rpc" "--continue")
        #:on-ready (lambda ()
                     ;; Render full session history to output buffer
                     (let ([session-path (get-latest-session-file (current-directory))])
                       (when session-path
                         (helix-append-output (render-session-file session-path))))))))

;; basename is now in pi-core.scm

(define (pi-get-sessions-dir)
  "Get the sessions directory path for current working directory."
  (get-sessions-dir (current-directory)))

(define (pi-get-session-files)
  "Get list of session files sorted by modification time (newest first)."
  (let* ([sessions-dir (pi-get-sessions-dir)]
         [result (spawn-process
                   (with-stdout-piped
                     (command "ls" (list "-t" sessions-dir))))])
    (if (Ok? result)
        (let* ([proc (Ok->value result)]
               [stdout-port (child-stdout proc)]
               [_ (wait proc)]
               [output (trim (read-port-to-string stdout-port))])
          (if (equal? output "")
              '()
              (map (lambda (f) (string-append sessions-dir "/" f))
                   (filter (lambda (s) (not (equal? s "")))
                           (split-whitespace output)))))
        '())))

(define (pi-resume-session path-or-filename)
  "Resume a specific session by path or filename."
  (let ([path (resolve-session-path path-or-filename (current-directory))])
    (if (pi-running?)
        ;; Already running - switch session via RPC
        (when (pi-rpc-send (pi-make-switch-session-request (pi-get-session) path))
          (pi-clear-output)
          ;; Render full session history immediately (response will confirm success)
          (helix-append-output (render-session-file path))
          (set-status! (string-append "pi: switched to " (basename path))))
        ;; Not running - spawn with --session
        (pi-spawn-process (list "--mode" "rpc" "--session" path)
          #:on-ready (lambda ()
                       (helix-append-output (render-session-file path)))))))

;;@doc
;; List available sessions in output buffer
(define (pi-sessions)
  (switch-to-output)
  (helix.static.goto_file_end)
  (helix.static.insert_string "\n## Available Sessions\n\n")
  (let ([sessions (pi-get-session-files)])
    (if (null? sessions)
        (helix.static.insert_string "No sessions found.\n")
        (begin
          (for-each (lambda (path)
                      (helix.static.insert_string (string-append "- " path "\n")))
                    sessions)
          (helix.static.insert_string
            "\nUse `:pi-resume` to pick, or put path in input and `:pi-resume`\n")))))

;;@doc
;; Resume a session. Shows picker if input empty, resumes path if provided.
(define (pi-resume)
  (define session-path (trim (pi-get-input)))
  (cond
    ;; If input has a path, use it
    [(not (equal? session-path ""))
     (pi-clear-input)
     (pi-resume-session session-path)]
    ;; Empty input - show picker
    [else
     (let ([sessions (pi-get-session-files)])
       (if (null? sessions)
           (set-status! "pi: no sessions found")
           (push-component!
             (picker-selection
               sessions
               (lambda (selected)
                 (pi-resume-session selected))
               #:preview-function
               (lambda (picker selection rect frame)
                 ;; Show just the filename in preview
                 (frame-set-string! frame 
                                    (+ 1 (area-x rect)) 
                                    (+ 1 (area-y rect)) 
                                    (basename selection) 
                                    (style)))
               #:highlight-prefix "> "))))]))

;;@doc
;; Send the input buffer contents to pi
(define (pi-send)
  (cond
    [(not (pi-running?))
     (set-status! "pi: not running (use :pi-start)")]
    [(pi-session-streaming? (pi-get-session))
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (when (pi-rpc-send (pi-make-follow-up-request (pi-get-session) text))
             (pi-clear-input)
             (set-status! "pi: queued follow-up"))))]
    [else
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (when (pi-rpc-send (pi-make-prompt-request (pi-get-session) text))
             (pi-clear-input)
             (set-status! "pi: sending..."))))]))

;;@doc
;; Abort the current pi operation
(define (pi-abort)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-rpc-send (pi-make-abort-request (pi-get-session)))
        (set-status! "pi: abort sent"))))

;;@doc
;; Quit the pi session
(define (pi-quit)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-cleanup!)
        (set-status! "pi: stopped (session saved)"))))

;;@doc
;; Force reset pi state (use if stuck due to process crash)
(define (pi-recover)
  (pi-cleanup!)
  (set! *pi-session* #f)
  (set-status! "pi: recovered (use :pi-start to restart)"))

;;@doc
;; Cycle to next model
(define (pi-model)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (pi-rpc-send (pi-make-cycle-model-request (pi-get-session)))))

;;@doc
;; Cycle thinking level
(define (pi-thinking)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (pi-rpc-send (pi-make-cycle-thinking-request (pi-get-session)))))

;;@doc
;; Compact conversation context
(define (pi-compact)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (set-status! "pi: compacting...")
        (pi-rpc-send (pi-make-compact-request (pi-get-session))))))

;;@doc
;; Start fresh session (without closing buffers)
(define (pi-new)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-rpc-send (pi-make-new-session-request (pi-get-session)))
        (pi-clear-output)
        (set-status! "pi: new session"))))

;;@doc
;; Show current status
(define (pi-status)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (pi-rpc-send (pi-make-get-state-request (pi-get-session)))))

;;@doc
;; Interrupt current operation with steering message
(define (pi-steer)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (let ([text (trim (pi-get-input))])
        (if (equal? text "")
            (set-status! "pi: empty steer message")
            (when (pi-rpc-send (pi-make-steer-request (pi-get-session) text))
              (pi-clear-input)
              (set-status! "pi: steer sent"))))))

;;@doc
;; Queue follow-up message explicitly
(define (pi-follow)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (let ([text (trim (pi-get-input))])
        (if (equal? text "")
            (set-status! "pi: empty follow-up")
            (when (pi-rpc-send (pi-make-follow-up-request (pi-get-session) text))
              (pi-clear-input)
              (set-status! "pi: follow-up queued"))))))

;;; ============ Exports ============
(provide pi-start pi-continue pi-sessions pi-resume pi-send pi-abort pi-quit pi-recover
         pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow)
