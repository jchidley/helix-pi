(require "system-theme-hx.scm")
(require "helix/ext.scm")
(require (only-in "helix/commands.scm" theme))
(require-builtin steel/time)

(provide auto-theme)

;; Automatically switch Helix theme based on system dark/light mode.
;; Polls in a background thread and only touches Helix when the theme changes.
;;
;; Usage:
;;   (auto-theme-watch "catppuccin-mocha" "catppuccin-latte")
;;
;; Arguments:
;;   dark        - Theme to use when the system is in dark mode
;;   light       - Theme to use when the system is in light mode
;;   interval-ms - (optional) Polling interval in milliseconds
;;                 Default: 1000ms (1 second)
(define (auto-theme dark light [interval-ms 1000])
  (define current-theme (detect))

  (if (equal? current-theme "dark")
    (theme dark)
    (theme light))

  (spawn-native-thread
    (lambda ()
      (let loop ()
        (time/sleep-ms interval-ms)

        (define detected (detect))

        (unless (equal? detected current-theme)
          (set! current-theme detected)

          (hx.with-context
            (lambda ()
              (if (equal? detected "dark")
                (theme dark)
                (theme light)))))

        (loop)))))
