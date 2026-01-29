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
   cb-send           ; (lambda (request) ...) - send RPC request
   ) #:mutable)

(define (make-pi-session #:append-output append-output
                         #:set-status set-status
                         #:on-unknown-event [on-unknown #f]
                         #:send [send #f])
  "Create a fresh session with injected callbacks."
  (pi-session #f                              ; not streaming
              (hash)                          ; no pending requests
              0                               ; request counter
              (hash)                          ; no tool output
              append-output
              set-status
              (or on-unknown (lambda (t) #f))
              send))

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

(define (session-send! session request)
  "Send a request via the session's send callback (if set)."
  (let ([cb (pi-session-cb-send session)])
    (when cb (cb request))))

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
  "Handle RPC response events - surface errors and state changes to user."
  (let* ([success (hash-try-get event 'success)]
         [command (hash-try-get event 'command)]
         [error-msg (hash-try-get event 'error)]
         [data (hash-try-get event 'data)]
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
      ;; Model cycling response
      [(equal? command "cycle_model")
       (when data
         (let ([model (hash-try-get data 'model)])
           (when model
             (let ([name (hash-try-get model 'name)])
               (session-set-status! session 
                 (string-append "pi: model → " (or name "unknown")))))))]
      ;; Thinking level response
      [(equal? command "cycle_thinking_level")
       (when data
         (let ([level (hash-try-get data 'level)])
           (session-set-status! session 
             (string-append "pi: thinking → " (or (to-string level) "unknown")))))]
      ;; Compact response
      [(equal? command "compact")
       (session-set-status! session "pi: compacted")]
      ;; New session response
      [(equal? command "new_session")
       (session-set-status! session "pi: new session")]
      ;; Get state response - display in output
      [(equal? command "get_state")
       (when data
         (let ([model (hash-try-get data 'model)]
               [thinking (hash-try-get data 'thinkingLevel)]
               [streaming (hash-try-get data 'isStreaming)]
               [messages (hash-try-get data 'messageCount)])
           (session-append-output! session
             (string-append "\n**Status**\n"
                            "- Model: " (or (and model (hash-try-get model 'name)) "?") "\n"
                            "- Thinking: " (or (to-string thinking) "?") "\n"
                            "- Streaming: " (if streaming "yes" "no") "\n"
                            "- Messages: " (to-string (or messages 0)) "\n\n"))))]
      ;; Switch session response - report status (UI handles rendering via on-ready callback)
      [(equal? command "switch_session")
       (let ([cancelled (and data (hash-try-get data 'cancelled))])
         (if cancelled
             (session-set-status! session "pi: switch cancelled")
             (session-set-status! session "pi: session loaded")))]
      [else #f])))

(define (truncate-text text max-len)
  "Truncate text to max-len chars, adding ... if truncated."
  (if (<= (string-length text) max-len)
      text
      (string-append "..." (substring text (- (string-length text) max-len) (string-length text)))))

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

(define (pi-make-cycle-model-request session)
  "Create a cycle_model RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "cycle_model")
    (hash "type" "cycle_model"
          "id" id)))

(define (pi-make-cycle-thinking-request session)
  "Create a cycle_thinking_level RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "cycle_thinking_level")
    (hash "type" "cycle_thinking_level"
          "id" id)))

(define (pi-make-compact-request session)
  "Create a compact RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "compact")
    (hash "type" "compact"
          "id" id)))

(define (pi-make-new-session-request session)
  "Create a new_session RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "new_session")
    (hash "type" "new_session"
          "id" id)))

(define (pi-make-get-state-request session)
  "Create a get_state RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "get_state")
    (hash "type" "get_state"
          "id" id)))

(define (pi-make-switch-session-request session path)
  "Create a switch_session RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "switch_session")
    (hash "type" "switch_session"
          "sessionPath" path
          "id" id)))

(define (pi-make-get-last-assistant-text-request session)
  "Create a get_last_assistant_text RPC request."
  (let ([id (next-request-id! session)])
    (register-pending! session id "get_last_assistant_text")
    (hash "type" "get_last_assistant_text"
          "id" id)))

;;; ============ Session File Utilities ============

(define (path-to-session-dir-name path)
  "Convert /home/jack/git/helix-pi to --home-jack-git-helix-pi--"
  (string-append "--" 
                 (string-replace (substring path 1 (string-length path)) "/" "-") 
                 "--"))

(define (get-sessions-dir cwd)
  "Get the sessions directory for a given working directory."
  (let* ([home (env-var "HOME")]
         [dir-name (path-to-session-dir-name cwd)])
    (string-append home "/.pi/agent/sessions/" dir-name)))

(define (resolve-session-path filename cwd)
  "Resolve a session filename to full path. If already absolute, return as-is."
  (if (and (> (string-length filename) 0)
           (equal? (substring filename 0 1) "/"))
      filename
      (string-append (get-sessions-dir cwd) "/" filename)))

(define (basename path)
  "Get the filename from a path."
  (let loop ([chars (reverse (string->list path))] [acc (list)])
    (cond
      [(null? chars) (list->string acc)]
      [(char=? (car chars) #\/) (list->string acc)]
      [else (loop (cdr chars) (cons (car chars) acc))])))

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

(define (parse-session-file-messages path)
  "Parse JSONL session file into list of (role . text-parts) pairs.
   Returns empty list if file doesn't exist or can't be parsed."
  (with-handler
    (lambda (err) '())
    (call-with-input-file path
      (lambda (port)
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
                            (loop messages))))))))))))

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

(define (render-session-file path)
  "Render a session JSONL file to markdown. Returns full rendered string."
  (format-session-history (parse-session-file-messages path)))

(define (render-session-file-tail path max-lines)
  "Render a session JSONL file to markdown, returning only the last max-lines."
  (let* ([full-text (render-session-file path)]
         [lines (split-lines full-text)]
         [num-lines (length lines)])
    (if (<= num-lines max-lines)
        full-text
        (string-append "...\n"
                       (join-lines (list-tail lines (- num-lines max-lines)))))))

(define (split-lines str)
  "Split string into list of lines."
  (let loop ([chars (string->list str)] [current '()] [lines '()])
    (cond
      [(null? chars)
       (reverse (if (null? current)
                    lines
                    (cons (list->string (reverse current)) lines)))]
      [(char=? (car chars) #\newline)
       (loop (cdr chars) '() (cons (list->string (reverse current)) lines))]
      [else
       (loop (cdr chars) (cons (car chars) current) lines)])))

(define (join-lines lines)
  "Join list of lines with newlines."
  (if (null? lines)
      ""
      (apply string-append
             (cons (car lines)
                   (map (lambda (line) (string-append "\n" line)) (cdr lines))))))

(define (split-whitespace str)
  "Split string on whitespace (spaces, tabs, newlines)."
  (let loop ([chars (string->list str)] [current '()] [words '()])
    (cond
      [(null? chars)
       (reverse (if (null? current)
                    words
                    (cons (list->string (reverse current)) words)))]
      [(or (char=? (car chars) #\space)
           (char=? (car chars) #\tab)
           (char=? (car chars) #\newline)
           (char=? (car chars) #\return))
       (if (null? current)
           (loop (cdr chars) '() words)
           (loop (cdr chars) '() (cons (list->string (reverse current)) words)))]
      [else
       (loop (cdr chars) (cons (car chars) current) words)])))

(define (get-latest-session-file cwd)
  "Get the path to the most recent session file for a working directory.
   Returns #f if no sessions exist."
  (let* ([sessions-dir (get-sessions-dir cwd)]
         [result (with-handler (lambda (e) #f)
                   ;; ls -t sorts by modification time, newest first
                   ;; Using shell to avoid reimplementing directory listing + sorting
                   (let* ([proc-result (spawn-process
                                         (with-stdout-piped
                                           (command "ls" (list "-t" sessions-dir))))]
                          [proc (if (Ok? proc-result) (Ok->value proc-result) #f)])
                     (if proc
                         (let* ([stdout-port (child-stdout proc)]
                                [_ (wait proc)]
                                [output (read-port-to-string stdout-port)]
                                [first-file (car (filter (lambda (s) (not (equal? s "")))
                                                         (split-whitespace output)))])
                           (string-append sessions-dir "/" first-file))
                         #f)))])
    result))

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
  pi-make-cycle-model-request
  pi-make-cycle-thinking-request
  pi-make-compact-request
  pi-make-new-session-request
  pi-make-get-state-request
  pi-make-switch-session-request
  pi-make-get-last-assistant-text-request
  
  ;; Session file utilities
  path-to-session-dir-name
  get-sessions-dir
  resolve-session-path
  basename
  get-text-parts
  parse-session-file-messages
  format-session-history
  render-session-file
  render-session-file-tail
  get-latest-session-file)
