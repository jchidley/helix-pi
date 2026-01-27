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

;; Setup mocks before tests
(define (setup-mocks!)
  (reset-captures!)
  (pi-set-callbacks! 
    #:append-output mock-append-output
    #:set-status mock-set-status
    #:on-unknown-event mock-on-unknown))

;;; ============ Event Handling Tests ============

(test-module
  "pi-handle-event"
  
  (setup-mocks!)
  
  ;; agent_start
  (check-equal? "agent_start sets streaming status"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "agent_start"))
      *captured-status*)
    "pi: streaming...")
  
  ;; agent_end  
  (check-equal? "agent_end sets idle status"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "agent_end"))
      *captured-status*)
    "pi: idle")
  
  (check-equal? "agent_end appends newlines"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "agent_end"))
      *captured-output*)
    "\n\n")
  
  ;; message_start - user
  (check-equal? "message_start user appends header"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_start" 
                             'message (hash 'role "user")))
      *captured-output*)
    "## You\n\n")
  
  ;; message_start - assistant
  (check-equal? "message_start assistant appends header"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_start"
                             'message (hash 'role "assistant")))
      *captured-output*)
    "## Assistant\n\n")
  
  ;; message_update with text_delta
  (check-equal? "message_update text_delta appends delta"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_update"
                             'assistantMessageEvent (hash 'type "text_delta"
                                                          'delta "Hello world")))
      *captured-output*)
    "Hello world")
  
  ;; message_update without delta (should not crash)
  (check-equal? "message_update without delta is safe"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_update"
                             'assistantMessageEvent (hash 'type "other")))
      *captured-output*)
    "")
  
  ;; message_end - user with content
  (check-equal? "message_end user appends content"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_end"
                             'message (hash 'role "user"
                                           'content (list (hash 'type "text" 'text "hello")))))
      *captured-output*)
    "hello\n\n")
  
  ;; message_end - assistant (no content appended)
  (check-equal? "message_end assistant no output"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "message_end"
                             'message (hash 'role "assistant")))
      *captured-output*)
    "")
  
  ;; tool_execution_start
  (check-equal? "tool_execution_start formats tool name"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "tool_execution_start"
                             'toolName "Bash"))
      *captured-output*)
    "\n**Bash**\n```\n")
  
  ;; tool_execution_end
  (check-equal? "tool_execution_end closes code block"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "tool_execution_end"))
      *captured-output*)
    "```\n\n")
  
  ;; Ignored events return #t but no output
  (check-equal? "turn_start returns true"
    (pi-handle-event (hash 'type "turn_start"))
    #t)
  
  (check-equal? "turn_end returns true"
    (pi-handle-event (hash 'type "turn_end"))
    #t)
  
  (check-equal? "response returns true"
    (pi-handle-event (hash 'type "response"))
    #t)
  
  ;; Unknown event
  (check-equal? "unknown event returns false"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "weird_event")))
    #f)
  
  (check-equal? "unknown event calls callback"
    (begin
      (reset-captures!)
      (pi-handle-event (hash 'type "weird_event"))
      *captured-unknown*)
    '("weird_event"))
)

;;; ============ RPC Construction Tests ============

(test-module
  "RPC message construction"
  
  (check-equal? "prompt request has correct type"
    (hash-ref (pi-make-prompt-request "hello") "type")
    "prompt")
  
  (check-equal? "prompt request has message"
    (hash-ref (pi-make-prompt-request "hello") "message")
    "hello")
  
  (check-equal? "prompt request has id"
    (string? (hash-ref (pi-make-prompt-request "hello") "id"))
    #t)
  
  (check-equal? "abort request has correct type"
    (hash-ref (pi-make-abort-request) "type")
    "abort")
  
  (check-equal? "abort request has id"
    (string? (hash-ref (pi-make-abort-request) "id"))
    #t)
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
)

;;; ============ Integration Test ============

(test-module
  "Full conversation flow"
  
  (setup-mocks!)
  (reset-captures!)
  
  ;; Simulate a full conversation
  (pi-handle-event (hash 'type "agent_start"))
  (pi-handle-event (hash 'type "turn_start"))
  (pi-handle-event (hash 'type "message_start" 'message (hash 'role "user")))
  (pi-handle-event (hash 'type "message_end" 'message (hash 'role "user" 
                                                            'content (list (hash 'type "text" 'text "hello")))))
  (pi-handle-event (hash 'type "message_start" 'message (hash 'role "assistant")))
  (pi-handle-event (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "Hi ")))
  (pi-handle-event (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "there!")))
  (pi-handle-event (hash 'type "message_end" 'message (hash 'role "assistant")))
  (pi-handle-event (hash 'type "turn_end"))
  (pi-handle-event (hash 'type "agent_end"))
  
  (check-equal? "full conversation output"
    *captured-output*
    "## You\n\nhello\n\n## Assistant\n\nHi there!\n\n")
  
  (check-equal? "final status is idle"
    *captured-status*
    "pi: idle")
)

(test-module
  "Conversation with tool use"
  
  (setup-mocks!)
  (reset-captures!)
  
  (pi-handle-event (hash 'type "agent_start"))
  (pi-handle-event (hash 'type "message_start" 'message (hash 'role "assistant")))
  (pi-handle-event (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta "Let me check.")))
  (pi-handle-event (hash 'type "tool_execution_start" 'toolName "Bash"))
  (pi-handle-event (hash 'type "tool_execution_end"))
  (pi-handle-event (hash 'type "message_update" 'assistantMessageEvent (hash 'type "text_delta" 'delta " Done!")))
  (pi-handle-event (hash 'type "message_end" 'message (hash 'role "assistant")))
  (pi-handle-event (hash 'type "agent_end"))
  
  (check-equal? "tool use output"
    *captured-output*
    "## Assistant\n\nLet me check.\n**Bash**\n```\n```\n\n Done!\n\n")
)
