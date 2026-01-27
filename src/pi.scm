;;; pi.scm - Helix integration for pi coding agent

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

;;; ============ Constants ============
(define PI-OUTPUT "pi/output")
(define PI-INPUT "pi/input")

;;; ============ State ============
(struct pi-state
  (session process stdin stdout stderr output-doc input-doc) #:mutable)

(define *pi* #f)

(define (pi-running?)
  (and *pi* (pi-state-process *pi*)))

(define (current-session)
  (and *pi* (pi-state-session *pi*)))

(define (pi-cleanup!)
  (when *pi*
    (let ([stdin (pi-state-stdin *pi*)])
      (when stdin
        (with-handler (lambda (e) #f)
          (close-output-port stdin))))
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
  (define output-exists (or (and *pi* (pi-state-output-doc *pi*))
                            (maybe-fetch-doc-id PI-OUTPUT)))
  (define input-exists (or (and *pi* (pi-state-input-doc *pi*))
                           (maybe-fetch-doc-id PI-INPUT)))
  
  (if (and output-exists input-exists)
      (begin
        (pi-clear-output)
        (pi-setup-window-layout))
      (begin
        (helix.hsplit-new)
        (set-scratch-buffer-name! (string-append "[" PI-OUTPUT "]"))
        (when *pi*
          (set-pi-state-output-doc! *pi* (editor->doc-id (editor-focus))))
        
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
  (if (not (pi-running?))
      #f
      (with-handler
        (lambda (err)
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
        [my-pi *pi*])
    (spawn-native-thread
      (lambda ()
        (let loop ()
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
                        (begin
                          (hx.block-on-task
                            (lambda ()
                              (displayln (string-append "pi: failed to parse: " (to-string line)))))
                          (loop))))
                  (hx.block-on-task
                    (lambda ()
                      (when (eq? *pi* my-pi)
                        (pi-session-reset! session)
                        (set! *pi* #f)
                        (set-status! "pi: process ended"))))))))))))

(define (try-parse-json str)
  (with-handler
    (lambda (err) #f)
    (string->jsexpr str)))

(define (safe-handle-event session event)
  (with-handler
    (lambda (err)
      (displayln (string-append "pi: event handler error: " (to-string err)))
      (when (pi-session? session)
        (pi-session-reset! session))
      (set-status! "pi: error (see log)"))
    (when (pi-session? session)
      (pi-handle-event session event))))

(define (pi-stderr-loop)
  (let ([stderr (pi-state-stderr *pi*)]
        [my-pi *pi*])
    (spawn-native-thread
      (lambda ()
        (let loop ()
          (when (eq? *pi* my-pi)
            (let ([line (read-line-from-port stderr)])
              (when (string? line)
                (hx.block-on-task
                  (lambda ()
                    (when (eq? *pi* my-pi)
                      (helix-append-output (string-append "\n**stderr**: " line "\n")))))
                (loop)))))))))

;;; ============ Process Spawn ============
(define (pi-spawn-process args)
  (pi-cleanup!)
  
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
            (set! *pi* (pi-state session
                                 child
                                 (child-stdin child)
                                 (child-stdout child)
                                 (child-stderr child)
                                 #f
                                 #f))
            
            (pi-create-buffers)
            (pi-event-loop)
            (pi-stderr-loop)
            (set-status! "pi: ready"))
          (set-status! "pi: failed to start process")))))

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
      (pi-spawn-process '("--mode" "rpc" "--continue"))))

;;@doc
;; Show picker to select and resume a session (placeholder)
(define (pi-resume)
  (set-status! "pi: resume not yet implemented"))

;;@doc
;; Send the input buffer contents to pi
(define (pi-send)
  (cond
    [(not (pi-running?))
     (set-status! "pi: not running (use :pi-start)")]
    [(pi-session-streaming? (current-session))
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

;;; ============ Exports ============
(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume pi-recover)
