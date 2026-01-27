;;; pi-core.scm - Pure Steel logic for pi coding agent (no helix dependencies)
;;;
;;; This module contains all testable logic:
;;;   - Session state management
;;;   - Event parsing and handling
;;;   - RPC message construction  
;;;   - Output text formatting
;;;   - Session file handling
;;;
;;; Helix-specific operations are injected via callbacks.

;;; ============ Session State ============
;;; All mutable state is encapsulated in a single struct

(struct pi-session
  (streaming?        ; #t if currently streaming
   pending-requests  ; hash of id -> command  
   request-counter   ; for generating unique IDs
   tool-output-lens  ; hash of tool-call-id -> output length seen
   ;; Callbacks (injected by helix layer)
   cb-append-output  ; (lambda (text) ...)
   cb-set-status     ; (lambda (msg) ...)
   cb-on-unknown     ; (lambda (type) ...)
   ) #:mutable)

(define (make-pi-session #:append-output append-output
                         #:set-status set-status
                         #:on-unknown-event [on-unknown #f])
  "Create a fresh session with injected callbacks."
  (pi-session #f                              ; not streaming
              (hash)                          ; no pending requests
              0                               ; request counter
              (hash)                          ; no tool output
              append-output
              set-status
              (or on-unknown (lambda (t) #f))))

(define (pi-session-reset! session)
  "Reset session state (but keep callbacks)."
  (set-pi-session-streaming?! session #f)
  (set-pi-session-pending-requests! session (hash))
  (set-pi-session-tool-output-lens! session (hash)))

;; Helper accessors for callbacks
(define (session-append-output! session text)
  (let ([cb (pi-session-cb-append-output session)])
    (when cb (cb text))))

(define (session-set-status! session msg)
  (let ([cb (pi-session-cb-set-status session)])
    (when cb (cb msg))))

;;; ============ Request ID Generation ============

(define (next-request-id! session)
  (let ([counter (+ 1 (pi-session-request-counter session))])
    (set-pi-session-request-counter! session counter)
    (string-append "req_" (number->string counter))))

(define (register-pending! session id command)
  (set-pi-session-pending-requests! session
    (hash-insert (pi-session-pending-requests session) id command)))

(define (resolve-pending! session id)
  "Resolve and remove a pending request. Returns command or #f."
  (let* ([pending (pi-session-pending-requests session)]
         [command (hash-try-get pending id)])
    (when command
      (set-pi-session-pending-requests! session
        (hash-insert pending id #f)))
    command))

;;; ============ Event Handling ============

(define (pi-handle-event session event)
  "Handle a parsed RPC event. Returns #t if handled, #f otherwise."
  (let ([type (hash-try-get event 'type)])
    (cond
      ;; Agent lifecycle
      [(equal? type "agent_start")
       (set-pi-session-streaming?! session #t)
       (session-set-status! session "pi: streaming...")
       #t]
      
      [(equal? type "agent_end")
       (set-pi-session-streaming?! session #f)
       (session-append-output! session "\n\n")
       (session-set-status! session "pi: idle")
       #t]
      
      ;; Message lifecycle  
      [(equal? type "message_start")
       (handle-message-start session event)
       #t]
      
      [(equal? type "message_update")
       (handle-message-update session event)
       #t]
      
      [(equal? type "message_end")
       (handle-message-end session event)
       #t]
      
      ;; Tool execution
      [(equal? type "tool_execution_start")
       (handle-tool-start session event)
       #t]
      
      [(equal? type "tool_execution_update")
       (handle-tool-update session event)
       #t]
      
      [(equal? type "tool_execution_end")
       (handle-tool-end session event)
       #t]
      
      ;; Lifecycle events (ignore)
      [(equal? type "turn_start") #t]
      [(equal? type "turn_end") #t]
      
      ;; Error events - critical for detecting stream failures
      [(equal? type "error")
       (handle-error-event session event)
       #t]
      
      [(equal? type "extension_error")
       (handle-extension-error session event)
       #t]
      
      ;; Auto-retry events - inform user of transient errors
      [(equal? type "auto_retry_start")
       (handle-auto-retry-start session event)
       #t]
      
      [(equal? type "auto_retry_end")
       (handle-auto-retry-end session event)
       #t]
      
      ;; RPC responses - handle errors
      [(equal? type "response")
       (handle-response session event)
       #t]
      
      [else 
       (let ([cb (pi-session-cb-on-unknown session)])
         (when cb (cb type)))
       #f])))

(define (handle-message-start session event)
  (let ([msg (hash-try-get event 'message)])
    (when msg
      (let ([role (hash-try-get msg 'role)])
        (cond
          [(equal? role "user")
           (session-append-output! session "## You\n\n")]
          [(equal? role "assistant")
           (session-append-output! session "## Assistant\n\n")]
          [else #f])))))

(define (handle-message-update session event)
  (let ([evt (hash-try-get event 'assistantMessageEvent)])
    (when evt
      (let ([evt-type (hash-try-get evt 'type)]
            [delta (hash-try-get evt 'delta)])
        (cond
          ;; Text content - stream directly
          [(equal? evt-type "text_delta")
           (when delta (session-append-output! session delta))]
          ;; Thinking content - show with visual marker
          [(equal? evt-type "thinking_start")
           (session-append-output! session "<thinking>\n")]
          [(equal? evt-type "thinking_delta")
           (when delta (session-append-output! session delta))]
          [(equal? evt-type "thinking_end")
           (session-append-output! session "\n</thinking>\n\n")]
          [else #f])))))

(define (handle-message-end session event)
  (let ([msg (hash-try-get event 'message)])
    (when msg
      (let ([role (hash-try-get msg 'role)])
        (when (equal? role "user")
          (let ([content (hash-try-get msg 'content)])
            (when content
              (for-each (lambda (part)
                          (when (equal? (hash-try-get part 'type) "text")
                            (session-append-output! session (hash-try-get part 'text))
                            (session-append-output! session "\n\n")))
                        content))))))))

(define (handle-tool-start session event)
  (let ([tool-name (hash-try-get event 'toolName)])
    (when tool-name
      (session-append-output! session 
        (string-append "\n**" (to-string tool-name) "**\n```\n")))))

(define (handle-tool-update session event)
  "Handle streaming tool output. partialResult contains accumulated output."
  (let ([tool-call-id (hash-try-get event 'toolCallId)]
        [partial-result (hash-try-get event 'partialResult)])
    (when (and tool-call-id partial-result)
      (let ([content (hash-try-get partial-result 'content)])
        (when content
          (let* ([text (extract-text-from-content content)]
                 [lens (pi-session-tool-output-lens session)]
                 [prev-len (or (hash-try-get lens tool-call-id) 0)]
                 [new-len (string-length text)])
            (when (> new-len prev-len)
              (session-append-output! session (substring text prev-len new-len))
              (set-pi-session-tool-output-lens! session
                (hash-insert lens tool-call-id new-len)))))))))

(define (handle-tool-end session event)
  "Handle tool completion. Show any final content not yet displayed."
  (let ([tool-call-id (hash-try-get event 'toolCallId)]
        [result (hash-try-get event 'result)])
    (when (and tool-call-id result)
      (let ([content (hash-try-get result 'content)])
        (when content
          (let* ([text (extract-text-from-content content)]
                 [lens (pi-session-tool-output-lens session)]
                 [prev-len (or (hash-try-get lens tool-call-id) 0)]
                 [new-len (string-length text)])
            (when (> new-len prev-len)
              (session-append-output! session (substring text prev-len new-len))))))))
  (session-append-output! session "```\n\n"))

(define (extract-text-from-content content)
  "Extract concatenated text from content array."
  (apply string-append
         (filter (lambda (x) x)
                 (map (lambda (part)
                        (if (equal? (hash-try-get part 'type) "text")
                            (or (hash-try-get part 'text) "")
                            #f))
                      content))))

(define (handle-error-event session event)
  "Handle error events from the agent stream."
  (let ([reason (hash-try-get event 'reason)]
        [error-msg (hash-try-get event 'error)])
    (set-pi-session-streaming?! session #f)
    (session-append-output! session 
      (string-append "\n**Error**: " (or error-msg reason "Unknown error") "\n\n"))
    (session-set-status! session 
      (string-append "pi: error - " (or reason "unknown")))))

(define (handle-extension-error session event)
  "Handle extension error events."
  (let ([error-msg (hash-try-get event 'error)]
        [ext-path (hash-try-get event 'extensionPath)])
    (session-append-output! session 
      (string-append "\n**Extension Error**"
                     (if ext-path (string-append " (" ext-path ")") "")
                     ": " (or error-msg "Unknown error") "\n\n"))
    (session-set-status! session "pi: extension error")))

(define (handle-auto-retry-start session event)
  "Handle auto-retry start - inform user of transient error."
  (let ([error-msg (hash-try-get event 'errorMessage)]
        [attempt (hash-try-get event 'attempt)]
        [max-attempts (hash-try-get event 'maxAttempts)])
    (session-append-output! session 
      (string-append "\n*Retrying ("
                     (if attempt (number->string attempt) "?")
                     "/"
                     (if max-attempts (number->string max-attempts) "?")
                     "): " (or error-msg "transient error") "*\n"))
    (session-set-status! session "pi: retrying...")))

(define (handle-auto-retry-end session event)
  "Handle auto-retry end."
  (let ([success (hash-try-get event 'success)]
        [final-error (hash-try-get event 'finalError)])
    (if success
        (session-set-status! session "pi: retry succeeded")
        (begin
          (set-pi-session-streaming?! session #f)
          (session-append-output! session 
            (string-append "\n**Retry Failed**: " (or final-error "Max retries exceeded") "\n\n"))
          (session-set-status! session "pi: retry failed")))))

(define (handle-response session event)
  "Handle RPC response events - surface errors to user."
  (let* ([success (hash-try-get event 'success)]
         [command (hash-try-get event 'command)]
         [error-msg (hash-try-get event 'error)]
         [id (hash-try-get event 'id)]
         [correlated-cmd (if id (resolve-pending! session id) #f)]
         [effective-cmd (or command correlated-cmd)])
    (cond
      [(not success)
       (set-pi-session-streaming?! session #f)
       (let ([error-context (if effective-cmd
                                (string-append " (" effective-cmd ")")
                                "")])
         (session-append-output! session 
           (string-append "\n**Error" error-context "**: " 
                          (or error-msg "Unknown error") "\n\n"))
         (session-set-status! session 
           (string-append "pi: error - " (or error-msg "unknown"))))]
      [(equal? effective-cmd "abort")
       (set-pi-session-streaming?! session #f)
       (session-set-status! session "pi: aborted")]
      [else #f])))

;;; ============ RPC Message Construction ============

(define (pi-make-prompt-request session message)
  "Create a prompt RPC request hash."
  (let ([id (next-request-id! session)])
    (register-pending! session id "prompt")
    (hash "type" "prompt" 
          "message" message 
          "id" id)))

(define (pi-make-abort-request session)
  "Create an abort RPC request hash."
  (let ([id (next-request-id! session)])
    (register-pending! session id "abort")
    (hash "type" "abort"
          "id" id)))

(define (pi-make-follow-up-request session message)
  "Create a follow_up RPC request (queued until agent idle)."
  (let ([id (next-request-id! session)])
    (register-pending! session id "follow_up")
    (hash "type" "follow_up"
          "message" message
          "id" id)))

(define (pi-make-steer-request session message)
  "Create a steer RPC request (interrupts current operation)."
  (let ([id (next-request-id! session)])
    (register-pending! session id "steer")
    (hash "type" "steer"
          "message" message
          "id" id)))

;;; ============ Session File Utilities ============

(define (path-to-session-dir-name path)
  "Convert /home/jack/git/helix-pi to --home-jack-git-helix-pi--"
  (string-append "--" 
                 (string-replace (substring path 1 (string-length path)) "/" "-") 
                 "--"))

(define (get-text-parts content)
  "Extract text strings from message content array."
  (if content
      (filter (lambda (x) x)
              (map (lambda (part)
                     (if (equal? (hash-try-get part 'type) "text")
                         (hash-try-get part 'text)
                         #f))
                   content))
      '()))

(define (parse-session-file-events port)
  "Parse events from a session file port. Returns list of (role . text-parts) pairs."
  (let loop ([messages '()])
    (let ([line (read-line-from-port port)])
      (if (not (string? line))
          (reverse messages)
          (if (= (string-length line) 0)
              (loop messages)
              (let ([event (string->jsexpr line)])
                (let ([type (hash-try-get event 'type)]
                      [msg (hash-try-get event 'message)])
                  (if (and (equal? type "message") msg)
                      (let ([role (hash-try-get msg 'role)]
                            [content (hash-try-get msg 'content)])
                        (let ([text-parts (get-text-parts content)])
                          (if (null? text-parts)
                              (loop messages)
                              (loop (cons (cons role text-parts) messages)))))
                      (loop messages)))))))))

(define (format-session-history messages)
  "Format parsed messages into display text. Returns string."
  (apply string-append
         (map (lambda (msg)
                (let ([role (car msg)]
                      [texts (cdr msg)])
                  (string-append
                    (cond
                      [(equal? role "user") "## You\n\n"]
                      [(equal? role "assistant") "## Assistant\n\n"]
                      [else ""])
                    (apply string-append
                           (map (lambda (text) (string-append text "\n\n")) texts)))))
              messages)))

;;; ============ Exports ============
;; provide must come after definitions in Steel

(provide
  ;; Session management
  make-pi-session
  pi-session?
  pi-session-streaming?
  pi-session-reset!
  
  ;; Event handling
  pi-handle-event
  
  ;; RPC construction
  pi-make-prompt-request
  pi-make-abort-request
  pi-make-follow-up-request
  pi-make-steer-request
  
  ;; Session file utilities
  path-to-session-dir-name
  get-text-parts
  parse-session-file-events
  format-session-history)
