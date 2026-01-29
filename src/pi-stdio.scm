;;; pi-stdio.scm - Pure Steel stdio client for pi coding agent
;;;
;;; Single-threaded CLI client using the same pi-core.scm as Helix.
;;; Useful for debugging and testing without Helix.
;;;
;;; Usage:
;;;   steel src/pi-stdio.scm              # new session
;;;   steel src/pi-stdio.scm --continue   # resume previous

(require-builtin steel/process)
(require "steel/result")
(require "pi-core.scm")

;;; ============ I/O Callbacks ============

(define (append-output text)
  (display text)
  (flush-output-port (current-output-port)))

(define (set-status msg)
  (displayln (string-append "--- " msg " ---")))

;;; ============ State ============

(define *process* #f)
(define *stdin* #f)
(define *stdout* #f)
(define *session* #f)
(define *running* #t)

;;; ============ Utilities ============

;;; ============ Process Management ============

(define (start-pi! args)
  (let ([result (spawn-process
                  (with-stdout-piped
                    (with-stderr-piped
                      (with-stdin-piped
                        (command "pi" args)))))])
    (if (Ok? result)
        (let ([child (unwrap-ok result)])
          (set! *process* child)
          (set! *stdin* (child-stdin child))
          (set! *stdout* (child-stdout child))
          (set! *session* (make-pi-session
                            #:append-output append-output
                            #:set-status set-status
                            #:on-unknown-event (lambda (type) #f)
                            #:send (lambda (req) (send-rpc! req))))
          (set-status "ready")
          #t)
        (begin
          (displayln "Error: failed to start pi process")
          #f))))

(define (stop-pi!)
  (when *process*
    (with-handler (lambda (e) #f)
      (close-output-port *stdin*))
    (set! *process* #f)
    (set! *stdin* #f)
    (set! *stdout* #f)
    (set! *session* #f)))

;;; ============ RPC Communication ============

(define (send-rpc! request)
  (when *stdin*
    (let ([json-str (value->jsexpr-string request)])
      (#%raw-write-string json-str *stdin*)
      (#%raw-write-string "\n" *stdin*)
      (flush-output-port *stdin*))))

(define (try-parse-json str)
  (with-handler (lambda (err) #f)
    (string->jsexpr str)))

(define (read-response awaiting-stream?)
  "Read events until idle. If awaiting-stream?, wait for agent_end; otherwise return on response."
  (let loop ([in-stream #f] [last-response #f])
    (let ([line (read-line-from-port *stdout*)])
      (when (string? line)
        (let ([event (try-parse-json line)])
          (when event
            (let ([type (hash-try-get event 'type)])
              (pi-handle-event *session* event)
              (cond
                [(equal? type "agent_start") (loop #t last-response)]
                [(equal? type "agent_end") (or last-response 'done)]
                [(equal? type "response")
                 (if (or in-stream awaiting-stream?)
                     (loop in-stream event)   ; save response, keep waiting
                     event)]                  ; non-streaming: return immediately
                [else (loop in-stream last-response)]))))))))

(define (send-and-wait! request)
  "Send request and wait for response (non-streaming commands)"
  (send-rpc! request)
  (read-response #f))

(define (send-prompt-and-wait! request)
  "Send prompt and wait for streaming to complete"
  (send-rpc! request)
  (read-response #t))

;;; ============ Command Handlers ============

(define (show-help)
  (displayln "
Commands:
  :help, :h, :?       Show this help
  :quit, :q           Exit
  :abort              Abort current operation
  :follow <text>      Queue follow-up message
  :steer <text>       Interrupt with steering message
  :model              Cycle to next model
  :thinking           Cycle thinking level
  :compact            Compact conversation context
  :new                Start fresh session
  :status             Show current state
  :sessions           List available sessions
  :resume <path>      Switch to specific session
  <text>              Send as prompt
"))

(define (show-status)
  (let ([resp (send-and-wait! (pi-make-get-state-request *session*))])
    (when (and resp (hash? resp))
      (let ([data (hash-try-get resp 'data)])
        (when data
          (displayln (string-append "Model: " (to-string (hash-try-get data 'model))))
          (displayln (string-append "Thinking: " (to-string (hash-try-get data 'thinkingLevel))))
          (displayln (string-append "Streaming: " (to-string (hash-try-get data 'isStreaming))))
          (displayln (string-append "Messages: " (to-string (hash-try-get data 'messageCount)))))))))

(define (cycle-model)
  (let ([resp (send-and-wait! (pi-make-cycle-model-request *session*))])
    (when (and resp (hash? resp))
      (let ([data (hash-try-get resp 'data)])
        (when data
          (let ([model (hash-try-get data 'model)])
            (when model
              (set-status (string-append "model: " (to-string (hash-try-get model 'name)))))))))))

(define (cycle-thinking)
  (let ([resp (send-and-wait! (pi-make-cycle-thinking-request *session*))])
    (when (and resp (hash? resp))
      (let ([data (hash-try-get resp 'data)])
        (when data
          (set-status (string-append "thinking: " (to-string (hash-try-get data 'level)))))))))

(define (compact-context)
  (set-status "compacting...")
  (send-and-wait! (pi-make-compact-request *session*))
  (set-status "compacted"))

(define (new-session)
  (send-and-wait! (pi-make-new-session-request *session*))
  (set-status "new session"))

(define (show-sessions)
  (let ([sessions-dir (get-sessions-dir (current-directory))])
    (displayln "\nSessions for this directory:")
    (displayln (string-append "  " sessions-dir))
    (displayln "")
    (flush-output-port (current-output-port))
    ;; List session files sorted by time
    (let ([result (spawn-process
                    (with-stdout-piped
                      (command "ls" (list "-lt" sessions-dir))))])
      (if (Ok? result)
          (let* ([proc (Ok->value result)]
                 [stdout-port (child-stdout proc)]
                 [_ (wait proc)]
                 [output (read-port-to-string stdout-port)])
            (displayln output)
            (displayln "Use :resume <filename> to switch")
            (flush-output-port (current-output-port)))
          (begin
            (displayln "  (no sessions found)")
            (flush-output-port (current-output-port)))))))

(define (switch-session filename)
  "Switch to a session. If just a filename, build full path from cwd.
   After switch, show tail of session history."
  (let ([path (resolve-session-path filename (current-directory))])
    (send-rpc! (pi-make-switch-session-request *session* path))
    ;; Read switch_session response
    (read-response #f)
    ;; Show tail of session history
    (displayln "---")
    (displayln (render-session-file-tail path 80))
    (displayln "---")
    (set-status (string-append "switched to " (basename path)))))

;;; ============ Input Parsing ============

(define (starts-with? str prefix)
  (and (>= (string-length str) (string-length prefix))
       (equal? (substring str 0 (string-length prefix)) prefix)))

(define (after-prefix str prefix)
  (trim (substring str (string-length prefix) (string-length str))))

(define (handle-input input)
  (cond
    ;; Help
    [(or (equal? input ":help") (equal? input ":h") (equal? input ":?"))
     (show-help)]
    
    ;; Exit
    [(or (equal? input ":quit") (equal? input ":q"))
     (set! *running* #f)
     (set-status "goodbye")]
    
    ;; Abort
    [(equal? input ":abort")
     (send-and-wait! (pi-make-abort-request *session*))]
    
    ;; Follow-up
    [(starts-with? input ":follow ")
     (send-and-wait! (pi-make-follow-up-request *session* (after-prefix input ":follow ")))]
    
    ;; Steer
    [(starts-with? input ":steer ")
     (send-and-wait! (pi-make-steer-request *session* (after-prefix input ":steer ")))]
    
    ;; Model cycling
    [(equal? input ":model")
     (cycle-model)]
    
    ;; Thinking level
    [(equal? input ":thinking")
     (cycle-thinking)]
    
    ;; Compact
    [(equal? input ":compact")
     (compact-context)]
    
    ;; New session
    [(equal? input ":new")
     (new-session)]
    
    ;; Status
    [(equal? input ":status")
     (show-status)]
    
    ;; Sessions - list available
    [(equal? input ":sessions")
     (show-sessions)]
    
    ;; Resume with path - switch session
    [(starts-with? input ":resume ")
     (switch-session (after-prefix input ":resume "))]
    
    ;; Resume without path - error
    [(equal? input ":resume")
     (displayln "Usage: :resume <session-path>")
     (displayln "Use :sessions to list available sessions")]
    
    ;; Empty - ignore
    [(equal? input "") #f]
    
    ;; Regular prompt
    [else
     (send-prompt-and-wait! (pi-make-prompt-request *session* input))]))

;;; ============ Main Loop ============

(define (repl)
  (let loop ()
    (when *running*
      (display "> ")
      (flush-output-port (current-output-port))
      (let ([input (read-line-from-port (current-input-port))])
        (if (string? input)
            (begin
              (handle-input (trim input))
              (loop))
            (set! *running* #f))))))

;;; ============ Entry Point ============

(define (show-resumed-context)
  "Show status and last ~80 lines of session history."
  ;; Request state - response includes sessionFile path
  (send-rpc! (pi-make-get-state-request *session*))
  (let ([resp (read-response #f)])
    ;; Extract sessionFile from get_state response
    (when (and resp (hash? resp))
      (let ([data (hash-try-get resp 'data)])
        (when data
          (let ([session-path (hash-try-get data 'sessionFile)])
            (when session-path
              (displayln "---")
              (displayln (render-session-file-tail session-path 80))
              (displayln "---"))))))))

(define (main)
  (let* ([args (command-line)]
         [continue? (member "--continue" args)]
         [pi-args (if continue? 
                      '("--mode" "rpc" "--continue")
                      '("--mode" "rpc"))])
    (displayln "pi-stdio - type :help for commands")
    (when continue? (displayln "(resuming previous session)"))
    (displayln "")
    
    (if (start-pi! pi-args)
        (begin
          ;; Show context when resuming
          (when continue? (show-resumed-context))
          (repl)
          (stop-pi!))
        (displayln "Failed to start pi"))))

(main)
