;;; pi.scm - MVP pi coding agent integration for Helix
;;; 
;;; Provides:
;;;   pi-start  - Start pi session (spawn process, create buffers)
;;;   pi-send   - Send input buffer contents to pi
;;;   pi-abort  - Abort current operation
;;;   pi-quit   - Close session (keeps session file for cache-friendly resume)
;;;
;;; Cache-friendly design:
;;;   - Uses pi sessions (not --no-session) for prompt caching
;;;   - Keeps process alive to maintain cached context
;;;   - Session persisted to ~/.pi/agent/sessions/ for later resume

(require-builtin steel/process)
(require "steel/result")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")
(require (only-in "helix/ext.scm" hx.block-on-task))
(require "mattwparas-helix-package/cogs/labelled-buffers.scm")
(require (only-in "mattwparas-helix-package/cogs/picker.scm" picker-selection))

(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume)

;;; ============ Constants ============

(define PI-OUTPUT "pi/output")
(define PI-INPUT "pi/input")

;; Get home directory via shell (cached)
(define *home-dir* #f)
(define (get-home-dir)
  (unless *home-dir*
    (let ([child (spawn-process (with-stdout-piped (command "printenv" '("HOME"))))])
      (when (Ok? child)
        (set! *home-dir* (trim (read-port-to-string (child-stdout (unwrap-ok child))))))))
  *home-dir*)

(define (pi-sessions-dir)
  (string-append (get-home-dir) "/.pi/agent/sessions"))

;;; ============ State ============

(define *pi-process* #f)      ; Child process handle
(define *pi-stdin* #f)        ; Write port
(define *pi-stdout* #f)       ; Read port  
(define *pi-request-id* 0)    ; Counter for request IDs
(define *pi-is-streaming* #f) ; Are we currently streaming?

;;; ============ Helpers ============

(define (next-request-id)
  (set! *pi-request-id* (+ *pi-request-id* 1))
  (string-append "req_" (number->string *pi-request-id*)))

(define (pi-running?)
  (and *pi-process* *pi-stdin* *pi-stdout*))

;;; ============ Buffer Management ============

(define (pi-create-buffers)
  ;; Check if buffers already exist
  (define output-exists (maybe-fetch-doc-id PI-OUTPUT))
  (define input-exists (maybe-fetch-doc-id PI-INPUT))
  
  (if (and output-exists input-exists)
      ;; Reuse existing buffers - just clear output
      (begin
        (pi-clear-output)
        (open-labelled-buffer PI-INPUT))
      ;; Create new buffers
      (begin
        ;; Create output buffer (left side for conversation)
        (make-new-labelled-buffer! #:label PI-OUTPUT #:side 'left)
        ;; Create input buffer (right side for editing prompts)  
        (make-new-labelled-buffer! #:label PI-INPUT #:side 'right)
        ;; Focus the input buffer
        (open-labelled-buffer PI-INPUT))))

(define (pi-clear-output)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-OUTPUT)
      (helix.static.select_all)
      (helix.static.delete_selection))))

(define (pi-append-output text)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-OUTPUT)
      (helix.static.goto_file_end)
      (helix.static.insert_string text))))

(define (pi-get-input)
  (define result "")
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-INPUT)
      (helix.static.select_all)
      (set! result (helix.static.current-highlighted-text!))))
  result)

(define (pi-clear-input)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-INPUT)
      (helix.static.select_all)
      (helix.static.delete_selection))))

;;; ============ RPC Communication ============

(define (pi-rpc-send command)
  (if (pi-running?)
      (let* ([id (next-request-id)]
             [json (hash-insert command "id" id)]
             [json-str (value->jsexpr-string json)])
        ;; Use raw write to avoid Scheme string quoting
        (#%raw-write-string json-str *pi-stdin*)
        (#%raw-write-string "\n" *pi-stdin*)
        (flush-output-port *pi-stdin*)
        id)
      #f))

(define (pi-rpc-prompt message)
  (pi-rpc-send (hash "type" "prompt" "message" message)))

(define (pi-rpc-abort)
  (pi-rpc-send (hash "type" "abort")))

(define (pi-rpc-get-state)
  (pi-rpc-send (hash "type" "get_state")))

;;; ============ Event Handling ============

(define (pi-handle-event event)
  (let ([type (hash-try-get event 'type)])
    (cond
      ;; Agent lifecycle
      [(equal? type "agent_start")
       (set! *pi-is-streaming* #t)
       (set-status! "pi: streaming...")]
      
      [(equal? type "agent_end")
       (set! *pi-is-streaming* #f)
       (pi-append-output "\n\n")
       (set-status! "pi: idle")]
      
      ;; Message lifecycle  
      [(equal? type "message_start")
       (let ([msg (hash-try-get event 'message)])
         (when msg
           (let ([role (hash-try-get msg 'role)])
             (cond
               [(equal? role "user")
                (pi-append-output "## You\n\n")]
               [(equal? role "assistant")
                (pi-append-output "## Assistant\n\n")]
               [else #f]))))]
      
      [(equal? type "message_update")
       (let ([evt (hash-try-get event 'assistantMessageEvent)])
         (when evt
           (let ([evt-type (hash-try-get evt 'type)])
             (when (equal? evt-type "text_delta")
               (let ([delta (hash-try-get evt 'delta)])
                 (when delta
                   (pi-append-output delta)))))))]
      
      [(equal? type "message_end")
       ;; For user messages, render the content here
       (let ([msg (hash-try-get event 'message)])
         (when msg
           (let ([role (hash-try-get msg 'role)])
             (when (equal? role "user")
               (let ([content (hash-try-get msg 'content)])
                 (when content
                   ;; content is a list, extract text parts
                   (for-each (lambda (part)
                               (when (equal? (hash-try-get part 'type) "text")
                                 (pi-append-output (hash-try-get part 'text))
                                 (pi-append-output "\n\n")))
                             content)))))))]
      
      ;; Tool execution
      [(equal? type "tool_execution_start")
       (let ([tool-name (hash-try-get event 'toolName)])
         (when tool-name
           (pi-append-output (string-append "\n**" (to-string tool-name) "**\n```\n"))))]
      
      [(equal? type "tool_execution_end")
       (pi-append-output "```\n\n")]
      
      ;; Turn lifecycle (ignore)
      [(equal? type "turn_start") #f]
      [(equal? type "turn_end") #f]
      
      ;; Response (command acknowledgment)
      [(equal? type "response") #f]
      
      [else 
       (displayln (string-append "Unknown event type: " (if type (to-string type) "nil")))
       #f])))

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

;; Convert directory name like "--home-jack-git-helix-pi--" to "~/git-helix-pi"
;; Note: pi encodes paths with - as separator, so helix-pi becomes helix-pi (ambiguous)
;; We show the mangled form but replace home prefix with ~
(define (session-dir-to-display-name dir-name)
  (let* ([;; Remove leading/trailing "--"
          stripped (if (and (> (string-length dir-name) 4)
                           (equal? (substring dir-name 0 2) "--")
                           (equal? (substring dir-name (- (string-length dir-name) 2) (string-length dir-name)) "--"))
                       (substring dir-name 2 (- (string-length dir-name) 2))
                       dir-name)]
         ;; Get home dir name (e.g., "jack" from "/home/jack")
         [home (get-home-dir)]
         [home-name (file-name home)]
         ;; Expected formats: "home-{username}" or "home-{username}-..."
         [home-exact (string-append "home-" home-name)]
         [home-prefix (string-append "home-" home-name "-")])
    (cond
      [(equal? stripped home-exact) "~"]
      [(starts-with? stripped home-prefix)
       (string-append "~/" (substring stripped (string-length home-prefix) (string-length stripped)))]
      [else stripped])))

;; Get most recent .jsonl file in a session directory
(define (get-latest-session-file session-dir)
  (let ([files (read-dir session-dir)])
    (let ([jsonl-files (filter (lambda (f) (ends-with? f ".jsonl")) files)])
      (if (null? jsonl-files)
          #f
          ;; Files are named with ISO timestamps, so sorting gives us chronological order
          (let ([sorted (sort jsonl-files string>?)])
            (car sorted))))))

;; Extract first user message from a session file (for picker display)
(define (get-first-user-message session-file)
  (call-with-input-file session-file
    (lambda (port)
      (let loop ()
        (let ([line (read-line-from-port port)])
          (if (not (string? line))
              "(empty)"
              (let ([event (string->jsexpr line)])
                (let ([type (hash-try-get event 'type)]
                      [msg (hash-try-get event 'message)])
                  (if (and (equal? type "message") 
                           msg 
                           (equal? (hash-try-get msg 'role) "user"))
                      ;; Found first user message, extract text
                      (let ([content (hash-try-get msg 'content)])
                        (if (and content (> (length content) 0))
                            (let* ([first-part (car content)]
                                   [text (hash-try-get first-part 'text)])
                              (if text
                                  ;; Truncate to ~50 chars for display
                                  (if (> (string-length text) 50)
                                      (string-append (substring text 0 47) "...")
                                      text)
                                  "(no text)"))
                            "(empty)"))
                      (loop))))))))))

;; Load and display session history in output buffer
;; Helper: extract text parts from message content
(define (get-text-parts content)
  (if content
      (filter (lambda (x) x)
              (map (lambda (part)
                     (if (equal? (hash-try-get part 'type) "text")
                         (hash-try-get part 'text)
                         #f))
                   content))
      '()))

(define (display-session-history session-file)
  (call-with-input-file session-file
    (lambda (port)
      (let loop ()
        (let ([line (read-line-from-port port)])
          ;; Skip empty lines and handle EOF (read-line-from-port may return eof object)
          (when (and (string? line) (> (string-length line) 0))
            (let ([event (string->jsexpr line)])
              (let ([type (hash-try-get event 'type)]
                    [msg (hash-try-get event 'message)])
                (when (and (equal? type "message") msg)
                  (let ([role (hash-try-get msg 'role)]
                        [content (hash-try-get msg 'content)])
                    (let ([text-parts (get-text-parts content)])
                      ;; Only show header if there's text content
                      (when (not (null? text-parts))
                        (cond
                          [(equal? role "user")
                           (pi-append-output "## You\n\n")
                           (for-each (lambda (text)
                                       (pi-append-output text)
                                       (pi-append-output "\n\n"))
                                     text-parts)]
                          [(equal? role "assistant")
                           (pi-append-output "## Assistant\n\n")
                           (for-each (lambda (text)
                                       (pi-append-output text)
                                       (pi-append-output "\n\n"))
                                     text-parts)]
                          [else #f])))))))
            (loop)))))))

;; List all available sessions as (display-name . session-file-path) pairs
(define (list-sessions)
  (if (path-exists? (pi-sessions-dir))
      (let ([dirs (read-dir (pi-sessions-dir))])
        (filter 
          (lambda (x) x)  ; Remove #f entries
          (map
            (lambda (dir)
              (let ([latest (get-latest-session-file dir)])
                (if latest
                    (let* ([dir-name (file-name dir)]
                           [display-name (session-dir-to-display-name dir-name)])
                      (cons display-name latest))
                    #f)))
            dirs)))
      '()))

;; Convert a path like /home/jack/git/helix-pi to session dir name --home-jack-git-helix-pi--
(define (path-to-session-dir-name path)
  (string-append "--" (string-replace (substring path 1 (string-length path)) "/" "-") "--"))

;; Get latest session file for current working directory
(define (get-cwd-latest-session)
  (let* ([cwd (current-directory)]
         [session-dir-name (path-to-session-dir-name cwd)]
         [session-dir (string-append (pi-sessions-dir) "/" session-dir-name)])
    (if (path-exists? session-dir)
        (get-latest-session-file session-dir)
        #f)))

;; List sessions for a specific directory (returns list of (display-name . file-path) pairs)
;; Display shows first user message, sorted newest first
(define (list-sessions-for-cwd)
  (let* ([cwd (current-directory)]
         [session-dir-name (path-to-session-dir-name cwd)]
         [session-dir (string-append (pi-sessions-dir) "/" session-dir-name)])
    (if (path-exists? session-dir)
        (let ([files (read-dir session-dir)])
          (let ([jsonl-files (filter (lambda (f) (ends-with? f ".jsonl")) files)])
            ;; Sort newest first
            (let ([sorted (sort jsonl-files string>?)])
              (map (lambda (f)
                     ;; Use first user message as display name
                     (let ([first-msg (get-first-user-message f)])
                       (cons first-msg f)))
                   sorted))))
        '())))

;; State for picker callback
(define *pi-session-map* (hash))

;;; ============ Commands ============

;;@doc
;; Start a NEW pi coding agent session (creates fresh session file)
;; For cache efficiency, prefer :pi-continue to resume previous session
(define (pi-start)
  (if (pi-running?)
      (set-status! "pi: already running")
      (pi-spawn-process '("--mode" "rpc") "")))

;;@doc
;; Continue previous pi session (cache-friendly - reuses cached context)
;; Shows full conversation history from last session
(define (pi-continue)
  (if (pi-running?)
      (set-status! "pi: already running")
      (let ([session-file (get-cwd-latest-session)])
        (if session-file
            (pi-spawn-process-with-history
              '("--mode" "rpc" "--continue")
              session-file)
            ;; No session found - start anyway (pi will create new)
            (pi-spawn-process '("--mode" "rpc" "--continue") "")))))

;;@doc
;; Show picker to select and resume a session from current directory
(define (pi-resume)
  (if (pi-running?)
      (set-status! "pi: already running")
      (let ([sessions (list-sessions-for-cwd)])
        (if (null? sessions)
            (set-status! "pi: no sessions found")
            (begin
              ;; Store session map for callback lookup
              (set! *pi-session-map*
                    (fold (lambda (pair acc)
                            (hash-insert acc (car pair) (cdr pair)))
                          (hash)
                          sessions))
              ;; Show picker
              (push-component!
                (picker-selection 
                  (map car sessions)
                  (lambda (selected)
                    (let ([session-file (hash-try-get *pi-session-map* selected)])
                      (if session-file
                          (pi-spawn-process-with-history
                            (list "--mode" "rpc" "--session" session-file)
                            session-file)
                          (set-status! "pi: session not found"))))
                  #:highlight-prefix "> ")))))))  ; picker, push-component, begin, if, let, if, define))

;; Internal: spawn pi process with given args
(define (pi-spawn-process args welcome-msg)
  (let ([result (spawn-process
                  (with-stdout-piped
                    (with-stdin-piped
                      (command "pi" args))))])
    (if (Ok? result)
        (let ([child (unwrap-ok result)])
          (set! *pi-process* child)
          (set! *pi-stdin* (child-stdin child))
          (set! *pi-stdout* (child-stdout child))
          
          ;; Create UI
          (pi-create-buffers)
          
          ;; Start event loop
          (pi-event-loop)
          
          ;; Show welcome
          (pi-append-output welcome-msg)
          (set-status! "pi: started"))
        (set-status! "pi: failed to start process"))))

;; Internal: spawn pi process and display session history
(define (pi-spawn-process-with-history args session-file)
  (let ([result (spawn-process
                  (with-stdout-piped
                    (with-stdin-piped
                      (command "pi" args))))])
    (if (Ok? result)
        (let ([child (unwrap-ok result)])
          (set! *pi-process* child)
          (set! *pi-stdin* (child-stdin child))
          (set! *pi-stdout* (child-stdout child))
          
          ;; Create UI
          (pi-create-buffers)
          
          ;; Start event loop
          (pi-event-loop)
          
          ;; Show history (looks like a live session)
          (display-session-history session-file)
          (pi-append-output "---\n\n")
          (set-status! "pi: ready"))
        (set-status! "pi: failed to start process"))))

;;@doc
;; Send the input buffer contents to pi
(define (pi-send)
  (if (not (pi-running?))
      (set-status! "pi: not running (use :pi-start)")
      (let ([text (trim (pi-get-input))])  ; Trim the input
        (if (equal? text "")
            (set-status! "pi: empty prompt")
            (begin
              (pi-rpc-prompt text)
              (pi-clear-input)
              (set-status! "pi: sending..."))))))

;;@doc
;; Abort the current pi operation
(define (pi-abort)
  (if (not (pi-running?))
      (set-status! "pi: not running")
      (begin
        (pi-rpc-abort)
        (set-status! "pi: abort sent"))))

;;@doc
;; Quit the pi session (session saved - use :pi-continue to resume)
(define (pi-quit)
  (when *pi-process*
    ;; Close the process gracefully - session file is preserved
    (close-output-port *pi-stdin*)  ; Signal EOF to pi
    (set! *pi-process* #f)
    (set! *pi-stdin* #f)
    (set! *pi-stdout* #f)
    (set! *pi-is-streaming* #f)
    (set-status! "pi: stopped (session saved - :pi-continue to resume)")))


