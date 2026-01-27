;;; pi-core.scm - Pure Steel logic for pi coding agent (no helix dependencies)
;;;
;;; This module contains all testable logic:
;;;   - Event parsing and handling
;;;   - RPC message construction  
;;;   - Output text formatting
;;;   - Session file handling
;;;
;;; Helix-specific operations are injected via callbacks.

(provide
  ;; Callback setters
  pi-set-callbacks!
  
  ;; Event handling
  pi-handle-event
  
  ;; RPC construction
  pi-make-prompt-request
  pi-make-abort-request
  
  ;; Session file utilities
  path-to-session-dir-name
  get-text-parts
  parse-session-file-events
  format-session-history)

;;; ============ Callbacks ============
;;; These are injected by the helix layer

(define *cb-append-output* #f)    ; (lambda (text) ...)
(define *cb-set-status* #f)       ; (lambda (msg) ...)
(define *cb-on-unknown-event* #f) ; (lambda (type) ...)

(define (pi-set-callbacks! #:append-output append-output
                           #:set-status set-status
                           #:on-unknown-event [on-unknown-event #f])
  (set! *cb-append-output* append-output)
  (set! *cb-set-status* set-status)
  (set! *cb-on-unknown-event* (or on-unknown-event (lambda (t) #f))))

;; Safe callback invocation
(define (append-output! text)
  (when *cb-append-output*
    (*cb-append-output* text)))

(define (set-status! msg)
  (when *cb-set-status*
    (*cb-set-status* msg)))

;;; ============ Event Handling ============

(define (pi-handle-event event)
  "Handle a parsed RPC event. Returns #t if handled, #f otherwise."
  (let ([type (hash-try-get event 'type)])
    (cond
      ;; Agent lifecycle
      [(equal? type "agent_start")
       (set-status! "pi: streaming...")
       #t]
      
      [(equal? type "agent_end")
       (append-output! "\n\n")
       (set-status! "pi: idle")
       #t]
      
      ;; Message lifecycle  
      [(equal? type "message_start")
       (handle-message-start event)
       #t]
      
      [(equal? type "message_update")
       (handle-message-update event)
       #t]
      
      [(equal? type "message_end")
       (handle-message-end event)
       #t]
      
      ;; Tool execution
      [(equal? type "tool_execution_start")
       (handle-tool-start event)
       #t]
      
      [(equal? type "tool_execution_update")
       (handle-tool-update event)
       #t]
      
      [(equal? type "tool_execution_end")
       (handle-tool-end event)
       #t]
      
      ;; Lifecycle events (ignore)
      [(equal? type "turn_start") #t]
      [(equal? type "turn_end") #t]
      [(equal? type "response") #t]
      
      [else 
       (when *cb-on-unknown-event*
         (*cb-on-unknown-event* type))
       #f])))

(define (handle-message-start event)
  (let ([msg (hash-try-get event 'message)])
    (when msg
      (let ([role (hash-try-get msg 'role)])
        (cond
          [(equal? role "user")
           (append-output! "## You\n\n")]
          [(equal? role "assistant")
           (append-output! "## Assistant\n\n")]
          [else #f])))))

(define (handle-message-update event)
  (let ([evt (hash-try-get event 'assistantMessageEvent)])
    (when evt
      (let ([evt-type (hash-try-get evt 'type)]
            [delta (hash-try-get evt 'delta)])
        (cond
          ;; Text content - stream directly
          [(equal? evt-type "text_delta")
           (when delta (append-output! delta))]
          ;; Thinking content - show with visual marker
          [(equal? evt-type "thinking_start")
           (append-output! "<thinking>\n")]
          [(equal? evt-type "thinking_delta")
           (when delta (append-output! delta))]
          [(equal? evt-type "thinking_end")
           (append-output! "\n</thinking>\n\n")]
          [else #f])))))

(define (handle-message-end event)
  (let ([msg (hash-try-get event 'message)])
    (when msg
      (let ([role (hash-try-get msg 'role)])
        (when (equal? role "user")
          (let ([content (hash-try-get msg 'content)])
            (when content
              (for-each (lambda (part)
                          (when (equal? (hash-try-get part 'type) "text")
                            (append-output! (hash-try-get part 'text))
                            (append-output! "\n\n")))
                        content))))))))

(define (handle-tool-start event)
  (let ([tool-name (hash-try-get event 'toolName)])
    (when tool-name
      (append-output! (string-append "\n**" (to-string tool-name) "**\n```\n")))))

;; Track last output length to compute deltas from accumulated results
(define *tool-output-lengths* (hash))

(define (handle-tool-update event)
  "Handle streaming tool output. partialResult contains accumulated output."
  (let ([tool-call-id (hash-try-get event 'toolCallId)]
        [partial-result (hash-try-get event 'partialResult)])
    (when (and tool-call-id partial-result)
      (let ([content (hash-try-get partial-result 'content)])
        (when content
          (let* ([text (extract-text-from-content content)]
                 [prev-len (or (hash-try-get *tool-output-lengths* tool-call-id) 0)]
                 [new-len (string-length text)])
            (when (> new-len prev-len)
              (append-output! (substring text prev-len new-len))
              (set! *tool-output-lengths* 
                    (hash-insert *tool-output-lengths* tool-call-id new-len)))))))))

(define (handle-tool-end event)
  "Handle tool completion. Show any final content not yet displayed."
  (let ([tool-call-id (hash-try-get event 'toolCallId)]
        [result (hash-try-get event 'result)])
    ;; If we have result content, show any text not yet streamed
    (when (and tool-call-id result)
      (let ([content (hash-try-get result 'content)])
        (when content
          (let* ([text (extract-text-from-content content)]
                 [prev-len (or (hash-try-get *tool-output-lengths* tool-call-id) 0)]
                 [new-len (string-length text)])
            (when (> new-len prev-len)
              (append-output! (substring text prev-len new-len))))))))
  (append-output! "```\n\n"))

(define (extract-text-from-content content)
  "Extract concatenated text from content array."
  (apply string-append
         (filter (lambda (x) x)
                 (map (lambda (part)
                        (if (equal? (hash-try-get part 'type) "text")
                            (or (hash-try-get part 'text) "")
                            #f))
                      content))))

;;; ============ RPC Message Construction ============

(define *request-counter* 0)

(define (next-request-id)
  (set! *request-counter* (+ *request-counter* 1))
  (string-append "req_" (number->string *request-counter*)))

(define (pi-make-prompt-request message)
  "Create a prompt RPC request hash."
  (hash "type" "prompt" 
        "message" message 
        "id" (next-request-id)))

(define (pi-make-abort-request)
  "Create an abort RPC request hash."
  (hash "type" "abort"
        "id" (next-request-id)))

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
