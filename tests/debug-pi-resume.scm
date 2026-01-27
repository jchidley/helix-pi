;;; Test script for debugging pi-resume
;;; Run these in Helix with :evalp

;; Test 1: Check if list-sessions-for-cwd works
;; :evalp (length (list-sessions-for-cwd))

;; Test 2: Check session labels  
;; :evalp (map car (list-sessions-for-cwd))

;; Test 3: Check session files
;; :evalp (map cdr (list-sessions-for-cwd))

;; Test 4: Check if picker-selection is available
;; :evalp picker-selection

;; Test 5: Test picker with simple list
;; :evalp (push-component! (picker-selection '("a" "b") (lambda (x) (displayln x)) #:highlight-prefix "> "))

;; Test 6: Check the session map after building
;; :evalp *pi-session-map*
