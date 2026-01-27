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

;;; ============ Commands ============
(define (pi-start)
  (if (pi-running?)
      (set-status! "pi: already running")
      (set-status! "pi: would start")))

(define (pi-continue)
  (set-status! "pi: continue"))

(define (pi-resume)
  (set-status! "pi: resume"))

(define (pi-send)
  (set-status! "pi: send"))

(define (pi-abort)
  (set-status! "pi: abort"))

(define (pi-quit)
  (if (not *pi*)
      (set-status! "pi: not running")
      (begin
        (pi-cleanup!)
        (set-status! "pi: stopped"))))

(define (pi-recover)
  (pi-cleanup!)
  (set-status! "pi: recovered"))

;;; ============ Exports ============
(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume pi-recover)
