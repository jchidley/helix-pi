;;; pi-core-test.scm - Tests for pi-core.scm
;;;
;;; Run with: steel test tests/

(require "steel/tests/unit-test.scm"
         (for-syntax "steel/tests/unit-test.scm"))
(require "../src/pi-core.scm")

(provide __module__)
(define __module__ "pi-core-test")

;;; ============ Test Helpers ============

;; Capture output from callbacks
(define *captured-output* "")
(define *captured-status* "")
(define *captured-unknown* '())

(define (reset-captures!)
  (set! *captured-output* "")
  (set! *captured-status* "")
  (set! *captured-unknown* '()))

(define (mock-append-output text)
  (set! *captured-output* (string-append *captured-output* text)))

(define (mock-set-status msg)
  (set! *captured-status* msg))

(define (mock-on-unknown type)
  (set! *captured-unknown* (cons type *captured-unknown*)))

;; Create a test session with mock callbacks
(define (make-test-session)
  (make-pi-session
    #:append-output mock-append-output
    #:set-status mock-set-status
    #:on-unknown-event mock-on-unknown))

;;; ============ Event Handling Tests ============

(test-module
  "pi-handle-event"
  
  ;; agent_start
  (check-equal? "agent_start sets streaming status"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        *captured-status*))
    "pi: streaming...")
  
  (check-equal? "agent_start sets streaming state"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-session-streaming? s)))
    #t)
  
  ;; agent_end  
  (check-equal? "agent_end sets idle status"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_end"))
        *captured-status*))
    "pi: idle")
  
  (check-equal? "agent_end appends newlines"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_end"))
        *captured-output*))
    "\n\n")
  
  (check-equal? "agent_end clears streaming state"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-handle-event s (hash 'type "agent_end"))
        (pi-session-streaming? s)))
    #f)
  
  ;; message_start - user
  (check-equal? "message_start user appends header"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_start" 
                                 'message (hash 'role "user")))
        *captured-output*))
    "## You\n\n")
  
  ;; message_start - assistant
  (check-equal? "message_start assistant appends header"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_start"
                                 'message (hash 'role "assistant")))
        *captured-output*))
    "## Assistant\n\n")
  
  ;; message_update with text_delta
  (check-equal? "message_update text_delta appends delta"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_update"
                                 'assistantMessageEvent (hash 'type "text_delta"
                                                              'delta "Hello world")))
        *captured-output*))
    "Hello world")
  
  ;; message_update without delta (should not crash)
  (check-equal? "message_update without delta is safe"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_update"
                                 'assistantMessageEvent (hash 'type "other")))
        *captured-output*))
    "")
  
  ;; message_end - user with content
  (check-equal? "message_end user appends content"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_end"
                                 'message (hash 'role "user"
                                               'content (list (hash 'type "text" 'text "hello")))))
        *captured-output*))
    "hello\n\n")
  
  ;; message_end - assistant (no content appended)
  (check-equal? "message_end assistant no output"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "message_end"
                                 'message (hash 'role "assistant")))
        *captured-output*))
    "")
  
  ;; tool_execution_start
  (check-equal? "tool_execution_start formats tool name"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "tool_execution_start"
                                 'toolName "Bash"))
        *captured-output*))
    "\n**Bash**\n```\n")
  
  ;; tool_execution_end
  (check-equal? "tool_execution_end closes code block"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "tool_execution_end"))
        *captured-output*))
    "```\n\n")
  
  ;; Ignored events return #t but no output
  (check-equal? "turn_start returns true"
    (let ([s (make-test-session)])
      (pi-handle-event s (hash 'type "turn_start")))
    #t)
  
  (check-equal? "turn_end returns true"
    (let ([s (make-test-session)])
      (pi-handle-event s (hash 'type "turn_end")))
    #t)
  
  (check-equal? "response returns true"
    (let ([s (make-test-session)])
      (pi-handle-event s (hash 'type "response" 'success #t)))
    #t)
  
  ;; Response error handling
  (check-equal? "response error shows message"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "response" 
                                 'success #f 
                                 'error "API key invalid"))
        *captured-output*))
    "\n**Error**: API key invalid\n\n")
  
  (check-equal? "response error sets status"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "response"
                                 'success #f
                                 'error "Rate limited"))
        *captured-status*))
    "pi: error - Rate limited")
  
  (check-equal? "response error with no message"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "response" 'success #f))
        *captured-output*))
    "\n**Error**: Unknown error\n\n")
  
  (check-equal? "response abort success sets status"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "response"
                                 'success #t
                                 'command "abort"))
        *captured-status*))
    "pi: aborted")
  
  ;; Error event handling
  (check-equal? "error event shows message"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "error"
                                 'reason "aborted"
                                 'error "Request was aborted"))
        *captured-output*))
    "\n**Error**: Request was aborted\n\n")
  
  (check-equal? "error event clears streaming"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-handle-event s (hash 'type "error" 'reason "error"))
        (pi-session-streaming? s)))
    #f)
  
  (check-equal? "error event sets status"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "error" 'reason "aborted"))
        *captured-status*))
    "pi: error - aborted")
  
  ;; Unknown event
  (check-equal? "unknown event returns false"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "weird_event"))))
    #f)
  
  (check-equal? "unknown event calls callback"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "weird_event"))
        *captured-unknown*))
    '("weird_event"))
)

;;; ============ RPC Construction Tests ============

(test-module
  "RPC message construction"
  
  (check-equal? "prompt request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-prompt-request s "hello") "type"))
    "prompt")
  
  (check-equal? "prompt request has message"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-prompt-request s "hello") "message"))
    "hello")
  
  (check-equal? "prompt request has id"
    (let ([s (make-test-session)])
      (string? (hash-ref (pi-make-prompt-request s "hello") "id")))
    #t)
  
  (check-equal? "abort request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-abort-request s) "type"))
    "abort")
  
  (check-equal? "abort request has id"
    (let ([s (make-test-session)])
      (string? (hash-ref (pi-make-abort-request s) "id")))
    #t)
  
  ;; Follow-up request
  (check-equal? "follow-up request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-follow-up-request s "more info") "type"))
    "follow_up")
  
  (check-equal? "follow-up request has message"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-follow-up-request s "more info") "message"))
    "more info")
  
  (check-equal? "follow-up request has id"
    (let ([s (make-test-session)])
      (string? (hash-ref (pi-make-follow-up-request s "more info") "id")))
    #t)
  
  ;; Steer request
  (check-equal? "steer request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-steer-request s "change direction") "type"))
    "steer")
  
  (check-equal? "steer request has message"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-steer-request s "change direction") "message"))
    "change direction")
  
  (check-equal? "steer request has id"
    (let ([s (make-test-session)])
      (string? (hash-ref (pi-make-steer-request s "change direction") "id")))
    #t)
  
  ;; Request IDs increment
  (check-equal? "request IDs increment"
    (let ([s (make-test-session)])
      (pi-make-prompt-request s "one")
      (pi-make-prompt-request s "two")
      (let ([req (pi-make-prompt-request s "three")])
        (hash-ref req "id")))
    "req_3")
  
  ;; Cycle model request
  (check-equal? "cycle-model request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-cycle-model-request s) "type"))
    "cycle_model")
  
  (check-equal? "cycle-model request has id"
    (let ([s (make-test-session)])
      (string? (hash-ref (pi-make-cycle-model-request s) "id")))
    #t)
  
  ;; Cycle thinking request
  (check-equal? "cycle-thinking request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-cycle-thinking-request s) "type"))
    "cycle_thinking_level")
  
  ;; Compact request
  (check-equal? "compact request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-compact-request s) "type"))
    "compact")
  
  ;; New session request
  (check-equal? "new-session request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-new-session-request s) "type"))
    "new_session")
  
  ;; Get state request
  (check-equal? "get-state request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-get-state-request s) "type"))
    "get_state")
  
  ;; Switch session request
  (check-equal? "switch-session request has correct type"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-switch-session-request s "/path/to/session") "type"))
    "switch_session")
  
  (check-equal? "switch-session request has path"
    (let ([s (make-test-session)])
      (hash-ref (pi-make-switch-session-request s "/path/to/session") "sessionPath"))
    "/path/to/session")
)

;;; ============ Session Utilities Tests ============

(test-module
  "Session utilities"
  
  (check-equal? "path-to-session-dir-name converts path"
    (path-to-session-dir-name "/home/jack/git/helix-pi")
    "--home-jack-git-helix-pi--")
  
  (check-equal? "path-to-session-dir-name handles simple path"
    (path-to-session-dir-name "/tmp")
    "--tmp--")
  
  (check-equal? "get-text-parts extracts text"
    (get-text-parts (list (hash 'type "text" 'text "hello")
                          (hash 'type "text" 'text "world")))
    '("hello" "world"))
  
  (check-equal? "get-text-parts filters non-text"
    (get-text-parts (list (hash 'type "text" 'text "hello")
                          (hash 'type "image" 'data "...")))
    '("hello"))
  
  (check-equal? "get-text-parts handles empty"
    (get-text-parts '())
    '())
  
  (check-equal? "get-text-parts handles #f"
    (get-text-parts #f)
    '())
  
  (check-equal? "format-session-history formats user message"
    (format-session-history '(("user" . ("hello"))))
    "## You\n\nhello\n\n")
  
  (check-equal? "format-session-history formats assistant message"
    (format-session-history '(("assistant" . ("hi there"))))
    "## Assistant\n\nhi there\n\n")
  
  (check-equal? "format-session-history formats conversation"
    (format-session-history '(("user" . ("hello"))
                              ("assistant" . ("hi"))))
    "## You\n\nhello\n\n## Assistant\n\nhi\n\n")
  
  (check-equal? "get-sessions-dir builds correct path"
    (get-sessions-dir "/home/jack/git/helix-pi")
    (string-append (env-var "HOME") "/.pi/agent/sessions/--home-jack-git-helix-pi--"))
  
  (check-equal? "resolve-session-path with absolute path"
    (resolve-session-path "/full/path/to/session.jsonl" "/home/jack")
    "/full/path/to/session.jsonl")
  
  (check-equal? "resolve-session-path with filename"
    (resolve-session-path "session.jsonl" "/home/jack/project")
    (string-append (env-var "HOME") "/.pi/agent/sessions/--home-jack-project--/session.jsonl"))
  
  (check-equal? "basename extracts filename"
    (basename "/home/jack/git/helix-pi/file.txt")
    "file.txt")
  
  (check-equal? "basename handles no directory"
    (basename "file.txt")
    "file.txt")
)

;;; ============ Session State Tests ============

(test-module
  "Session state management"
  
  (check-equal? "new session is not streaming"
    (let ([s (make-test-session)])
      (pi-session-streaming? s))
    #f)
  
  (check-equal? "pi-session-reset! clears streaming"
    (let ([s (make-test-session)])
      (pi-handle-event s (hash 'type "agent_start"))
      (pi-session-reset! s)
      (pi-session-streaming? s))
    #f)
  
  (check-equal? "session is a pi-session"
    (let ([s (make-test-session)])
      (pi-session? s))
    #t)
)

;;; ============ Request/Response Correlation Tests ============

(test-module
  "Request/response correlation"
  
  ;; Error response with correlation shows command context
  (check-equal? "error with correlation includes command"
    (begin
      (reset-captures!)
      (let* ([s (make-test-session)]
             [req (pi-make-prompt-request s "test")]
             [id (hash-ref req "id")])
        (pi-handle-event s (hash 'type "response"
                                 'success #f
                                 'error "API key missing"
                                 'id id))
        ;; Should include (prompt) in error message
        (string-contains? *captured-output* "(prompt)")))
    #t)
  
  ;; Error response without id still works
  (check-equal? "error without id still shows message"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "response"
                                 'success #f
                                 'error "Generic error"))
        (string-contains? *captured-output* "Generic error")))
    #t)
  
  ;; Abort request correlates correctly  
  (check-equal? "abort correlation sets status"
    (begin
      (reset-captures!)
      (let* ([s (make-test-session)]
             [req (pi-make-abort-request s)]
             [id (hash-ref req "id")])
        (pi-handle-event s (hash 'type "response"
                                 'success #t
                                 'id id))
        *captured-status*))
    "pi: aborted")
)

;;; ============ Integration Tests ============

(test-module
  "Full conversation flow"
  
  (check-equal? "full conversation output"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        ;; Simulate a full conversation
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-handle-event s (hash 'type "turn_start"))
        (pi-handle-event s (hash 'type "message_start" 'message (hash 'role "user")))
        (pi-handle-event s (hash 'type "message_end" 'message (hash 'role "user" 
                                                                    'content (list (hash 'type "text" 'text "hello")))))
        (pi-handle-event s (hash 'type "message_start" 'message (hash 'role "assistant")))
        (pi-handle-event s (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "Hi ")))
        (pi-handle-event s (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "there!")))
        (pi-handle-event s (hash 'type "message_end" 'message (hash 'role "assistant")))
        (pi-handle-event s (hash 'type "turn_end"))
        (pi-handle-event s (hash 'type "agent_end"))
        *captured-output*))
    "## You\n\nhello\n\n## Assistant\n\nHi there!\n\n")
  
  (check-equal? "final status is idle"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-handle-event s (hash 'type "agent_end"))
        *captured-status*))
    "pi: idle")
)

(test-module
  "Conversation with tool use"
  
  (check-equal? "tool use output"
    (begin
      (reset-captures!)
      (let ([s (make-test-session)])
        (pi-handle-event s (hash 'type "agent_start"))
        (pi-handle-event s (hash 'type "message_start" 'message (hash 'role "assistant")))
        (pi-handle-event s (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "Let me check.")))
        (pi-handle-event s (hash 'type "tool_execution_start" 'toolName "Bash"))
        (pi-handle-event s (hash 'type "tool_execution_end"))
        (pi-handle-event s (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta " Done!")))
        (pi-handle-event s (hash 'type "message_end" 'message (hash 'role "assistant")))
        (pi-handle-event s (hash 'type "agent_end"))
        *captured-output*))
    "## Assistant\n\nLet me check.\n**Bash**\n```\n```\n\n Done!\n\n")
)
