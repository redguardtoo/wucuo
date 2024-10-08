;;; wucuo.el --- Fastest solution to spell check camel case code or plain text -*- lexical-binding: t; -*-

;; Copyright (C) 2018-2023 Chen Bin
;;
;; Version: 0.3.2
;; Keywords: convenience
;; Author: Chen Bin <chenbin DOT sh AT gmail DOT com>
;; URL: http://github.com/redguardtoo/wucuo
;; Package-Requires: ((emacs "25.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary:
;;
;; 1. Setup
;; Please install either aspell or hunspell and their dictionaries.
;;
;; 2. Usage
;; Insert below code into ".emacs",
;;   (add-hook 'prog-mode-hook 'wucuo-start)
;;   (add-hook 'text-mode-hook 'wucuo-start)
;;
;; The spell checking starts when current buffer is saved.
;;
;; Please note `flyspell-prog-mode' and `flyspell-mode' should be turned off
;; before using this program.
;;
;; User's configuration for the package flyspell still works.
;; Flyspell provides two minor modes, `flyspell-prog-mode' and `flyspell-mode'.
;; They are replaced by this program.  But all the other commands and configuration
;; for flyspell is still valid.
;;
;; 3. Tips
;;
;; - `wucuo-spell-check-file' checks one file and report typos
;; - `wucuo-spell-check-directory' checks files in one directory and report typos
;;
;; - If `wucuo-flyspell-start-mode' is "normal", `wucuo-start' runs `flyspell-buffer'
;;   and `wucuo-spell-check-buffer-max' specifies maximum size of buffer to check.
;;   If it's "fast", `wucuo-start' runs `flyspell-region' on current visible region
;;   and `wucuo-spell-check-region-max' specifies maximum size of the region to check.
;;
;; - The interval of checking is set by `wucuo-update-interval'
;;
;; - See `wucuo-check-nil-font-face' on how to check plain text (text without font)
;;
;; - Use `wucuo-current-font-face' to detect font face at point
;;
;; - Set `wucuo-font-faces-to-check' or `wucuo-personal-font-faces-to-check' to specify
;; font faces to spell check
;;
;; - You can define a function in `wucuo-spell-check-buffer-predicate'.
;;   If the function returns t, the spell checking of current buffer will continue.
;;   If it returns nil, the spell checking is skipped.
;;
;; Here is sample to skip checking in specified major modes,
;;   (setq wucuo-spell-check-buffer-predicate
;;         (lambda ()
;;           (not (memq major-mode
;;                      '(dired-mode
;;                        log-edit-mode
;;                        compilation-mode
;;                        help-mode
;;                        profiler-report-mode
;;                        speedbar-mode
;;                        gud-mode
;;                        calc-mode
;;                        Info-mode)))))
;;
;; This program assumes Flyspell is already set up properly.
;; If you have problems on Flyspell configuration, check wucuo's README.
;;
;; To ignore specific typo, you can set `wucuo-extra-predicate'.
;;
;; This program can be run in Linux terminal as batch script.
;; See README for more details.

;;; Code:
(require 'flyspell)
(require 'font-lock)
(require 'cl-lib)
(require 'find-lisp)
(require 'wucuo-sdk)

(defgroup wucuo nil
  "Code spell checker."
  :group 'flyspell)

(defcustom wucuo-debug nil
  "Output debug information when it's not nil."
  :type 'boolean
  :group 'wucuo)

(defcustom wucuo-inherit-flyspell-mode-keybindings t
  "Inherit `flyspell-mode' keybindings."
  :type 'boolean
  :group 'wucuo)

(defcustom wucuo-flyspell-check-doublon t
  "Mark doublon (double words) as typo."
  :type 'boolean
  :group 'wucuo)

(defcustom wucuo-enable-camel-case-algorithm-p t
  "Enable slower Lisp spell check algorithm for camel case word."
  :type 'boolean
  :group 'wucuo)

(defcustom wucuo-enable-extra-typo-detection-algorithm-p t
  "Enable extra smart typo detection algorithm."
  :type 'boolean
  :group 'wucuo)

(defcustom wucuo-flyspell-start-mode "fast"
  "If it's \"normal\", run `flyspell-buffer' in `after-save-hook'.
If it's \"fast\", run `flyspell-region' in `after-save-hook' to check visible
region in current window."
  :type '(choice (string :tag "normal")
                 (string :tag "fast"))
  :group 'wucuo)

(defcustom wucuo-check-nil-font-face 'text
  "If nil, ignore plain text (text without font face).
If it's \"text\", check plain text in `text-mode' only.
If it's \"prog\", check plain text in `prog-mode' only.
If it's t, check plain text in any mode."
  :type 'sexp
  :group 'wucuo)

(defcustom wucuo-aspell-language-to-use "en"
  "Language to use passed to aspell option '--lang'.
Please note it's only to check camel cased words.
User's original dictionary configuration for flyspell still works."
  :type 'string
  :group 'wucuo)

(defcustom wucuo-hunspell-dictionary-base-name "en_US"
  "Dictionary base name pass to hunspell option '-d'.
Please note it's only used to check camel cased words.
User's original dictionary configuration for flyspell still works."
  :type 'string
  :group 'wucuo)

;; @see https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html
(defcustom wucuo-font-faces-to-check
  '(font-lock-string-face
    font-lock-doc-face
    font-lock-comment-face
    ;; font-lock-builtin-face ; names of built-in functions.
    font-lock-function-name-face
    font-lock-variable-name-face
    ;; font-lock-type-face ; names of user-defined data types

    ;; tree-sitter
    tree-sitter-hl-face:type
    tree-sitter-hl-face:string
    tree-sitter-hl-face:string.special
    tree-sitter-hl-face:doc
    tree-sitter-hl-face:comment
    tree-sitter-hl-face:property
    tree-sitter-hl-face:variable
    tree-sitter-hl-face:varialbe.parameter
    tree-sitter-hl-face:function
    tree-sitter-hl-face:function.call
    tree-sitter-hl-face:method
    tree-sitter-hl-face:method.call

    ;; javascript
    js2-function-call
    js2-function-param
    js2-object-property
    js2-object-property-access

    ;; css
    css-selector
    css-property

    ;; ReactJS
    rjsx-text
    rjsx-tag
    rjsx-attr)
  "Only check word whose font face is among this list.
If major mode's own predicate is not nil, the font face check is skipped."
  :type '(repeat sexp)
  :group 'wucuo)

(defcustom wucuo-personal-font-faces-to-check
  nil
  "Similar to `wucuo-font-faces-to-check'.  Define personal font faces to check.
If major mode's own predicate is not nil, the font face check is skipped."
  :type '(repeat sexp)
  :group 'wucuo)

(defcustom wucuo-update-interval 2
  "Interval (seconds) for `wucuo-spell-check-buffer' to call `flyspell-buffer'."
  :group 'wucuo
  :type 'integer)

(defcustom wucuo-spell-check-buffer-max (* 4 1024 1024)
  "Max size of buffer to run `flyspell-buffer'."
  :type 'integer
  :group 'wucuo)

(defcustom wucuo-spell-check-region-max (* 1000 80)
  "Max size of region to run `flyspell-region'."
  :type 'integer
  :group 'wucuo)

(defcustom wucuo-find-file-regexp ".*"
  "The file found in `wucuo-spell-check-directory' matches this regex."
  :type 'string
  :group 'wucuo)

(defcustom wucuo-exclude-file-regexp
  "^.*\\.\\(o\\|a\\|lib\\|elc\\|pyc\\|mp[34]\\|mkv\\|avi\\|mpeg\\|docx?\\|xlsx?\\|pdf\\|png\\|jpe?g\\|gif\\|tiff\\|session\\|yas-compiled-snippets.el\\)\\|TAGS\\|tags$"
  "The file found in `wucuo-spell-check-directory' does not match this regex."
  :type 'string
  :group 'wucuo)

(defcustom wucuo-exclude-directories
  '(
    ".cache"
    ".cask"
    ".cvs"
    ".git"
    ".gradle"
    ".npm"
    ".sass-cache"
    ".svn"
    ".tox"
    "bower_components"
    "build"
    "dist"
    "elpa"
    "node_modules"
    )
  "The directories skipped by `wucuo-spell-check-directory'.
Please note the directory name should not contain any slash character."
  :type '(repeat string)
  :group 'wucuo)

(defvar wucuo-spell-check-buffer-predicate nil
  "Function to test if current buffer is checked by `wucuo-spell-check-buffer'.
Returns t to continue checking, nil otherwise.")

(defcustom wucuo-modes-whose-predicate-ignored
  '(typescript-mode)
  "Major modes whose own predicates should be ignored."
  :type '(repeat sexp)
  :group 'wucuo)

(defcustom wucuo-extra-predicate '(lambda (word) t)
  "A callback to check WORD.  Return t if WORD is typo."
  :type 'function
  :group 'wucuo)

(defvar wucuo-extra-typo-detection-algorithms
  '(wucuo-flyspell-html-verify
    wucuo-flyspell-org-verify)
  "Extra Algorithms to test typos.")

(defvar wucuo-double-check-font-faces '(font-lock-string-face)
  "Font faces to double check typo.")

;; Timer to run auto-update tags file
(defvar wucuo-timer nil "Internal timer.")

(declare-function markdown-flyspell-check-word-p "markdown-mode")
(declare-function wucuo-flyspell-org-verify "wucuo-flyspell-org")
(declare-function wucuo-flyspell-html-verify "wucuo-flyspell-html")

;;;###autoload
(defun wucuo-register-extra-typo-detection-algorithms ()
  "Register extra typo detection algorithms."
  (autoload 'markdown-flyspell-check-word-p "markdown-mode" nil)
  (dolist (a wucuo-extra-typo-detection-algorithms)
    (autoload a (symbol-name a) nil)))

;; register autoload right now
(wucuo-register-extra-typo-detection-algorithms)

;;;###autoload
(defun wucuo-current-font-face (&optional quiet)
  "Get font face under cursor.
If QUIET is t, font face is not output."
  (interactive)
  (let* ((rlt (format "%S" (wucuo-sdk-get-font-face (point)))))
    (kill-new rlt)
    (unless quiet (message rlt))))

;;;###autoload
(defun wucuo-split-camel-case (word)
  "Split camel case WORD into a list of strings.
Ported from \"https://github.com/fatih/camelcase/blob/master/camelcase.go\"."
  (let* ((case-fold-search nil)
         (len (length word))
         ;; 64 sub-words is enough
         (runes (vector nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                 nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                 nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
                 nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil))
         (runes-length 0)
         (i 0)
         ch
         (last-class 0)
         (class 0)
         rlt)

    ;; split into fields based on class of character
    (while (< i len)
      (setq ch (elt word i))
      (cond
       ;; lower case
       ((and (>= ch ?a) (<= ch ?z))
        (setq class 1))
       ;; upper case
       ((and (>= ch ?A) (<= ch ?Z))
        (setq class 2))
       ((and (>= ch ?0) (<= ch ?9))
        (setq class 3))
       (t
        (setq class 4)))

      (cond
       ((= class last-class)
        (aset runes
              (1- runes-length)
              (concat (aref runes (1- runes-length)) (char-to-string ch))))
       (t
        (aset runes runes-length (char-to-string ch))
        (setq runes-length (1+ runes-length))))
      (setq last-class class)
      ;; end of while
      (setq i (1+ i)))

    ;; handle upper case -> lower case sequences, e.g.
    ;;     "PDFL", "oader" -> "PDF", "Loader"
    (setq i 0)
    (while (< i (1- runes-length))
      (let* ((ch-first (aref (aref runes i) 0))
             (ch-second (aref (aref runes (1+ i)) 0)))
        (when (and (and (>= ch-first ?A) (<= ch-first ?Z))
                   (and (>= ch-second ?a) (<= ch-second ?z)))
          (aset runes (1+ i) (concat (substring (aref runes i) -1) (aref runes (1+ i))))
          (aset runes i (substring (aref runes i) 0 -1))))
      (setq i (1+ i)))

    ;; construct final result
    (setq i 0)
    (while (< i runes-length)
      (when (> (length (aref runes i)) 0)
        (push (aref runes i) rlt))
      (setq i (1+ i)))
    (nreverse rlt)))

(defun wucuo-spell-checker-to-string (line)
  "Feed LINE into spell checker and return output as string."
  (let* ((cmd (cond
               ;; aspell: `echo "helle world" | aspell pipe --lang en`
               ((string-match-p "aspell\\(\\.exe\\)?$" ispell-program-name)
                (format "%s pipe --lang %s" ispell-program-name wucuo-aspell-language-to-use))
               ;; hunspell: `echo "helle world" | hunspell -a -d en_US`
               (t
                (format "%s -a -d %s" ispell-program-name wucuo-hunspell-dictionary-base-name))))
         rlt)
    (with-temp-buffer
      (call-process-region line ; feed line into process
                           nil ; ignored
                           shell-file-name
                           nil ; don't delete
                           t
                           nil
                           shell-command-switch
                           cmd)
      (setq rlt (buffer-substring-no-properties (point-min) (point-max))))
    (when wucuo-debug (message "wucuo-spell-checker-to-string => cmd=%s rlt=%s" cmd rlt))
    rlt))

;;;###autoload
(defun wucuo-check-camel-case-word-predicate (word)
  "Use aspell to check WORD.  If it's typo return t."
  (if (string-match-p "^&" (wucuo-spell-checker-to-string word)) t))

(defun wucuo-handle-sub-word (sub-word)
  "If return empty string, SUB-WORD is not checked by spell checker."
  (cond
   ;; don't check 1/2 character word
   ((< (length sub-word) 3)
    "")
   ;; don't  check word containing special character
   ((not (string-match-p "^[a-zA-Z]*$" sub-word))
    "")
   (t
    sub-word)))

(defmacro wucuo--get-mode-predicate ()
  "Get per mode predicate."
  `(unless (memq major-mode wucuo-modes-whose-predicate-ignored)
     (get major-mode 'flyspell-mode-predicate)))

(defun wucuo--font-matched-p (font-faces)
  "Verify if any of FONT-FACES should be spell checked."

  ;; multiple font faces at one point
  (when (and (not (listp font-faces))
             (not (null font-faces)))
    (setq font-faces (list font-faces)))

  (or (cl-intersection font-faces wucuo-font-faces-to-check)
      (cl-intersection font-faces wucuo-personal-font-faces-to-check)
      (and (null font-faces)
           (or (eq t wucuo-check-nil-font-face)
               (and (eq wucuo-check-nil-font-face 'text)
                    (derived-mode-p 'text-mode))
               (and (eq wucuo-check-nil-font-face 'prog)
                    (derived-mode-p 'prog-mode))))))

(defun wucuo-major-mode-html-p ()
  "Major mode is handling html like file."
  ;; no one uses html-mode now
  (or (derived-mode-p 'nxml-mode)
      (eq major-mode 'web-mode)))

;;;###autoload
(defun wucuo-typo-p (word)
  "Spell check WORD and return t if it's typo.
This is slow because new shell process is created."
  (save-excursion
    (with-temp-buffer
      (insert word)
      (font-lock-ensure)
      (flyspell-word)
      (let* ((overlays (overlays-at (point-min))))
        (and overlays (flyspell-overlay-p (car overlays)))))))

(defun wucuo-aspell-incorrect-typo-p (word)
  "Aspell wrongly regards a WORD near single quote as typo."
  (let* ((typo-p t))
    (when (and (string-match "aspell\\(\\.exe\\)?$" ispell-program-name)
               (memq (wucuo-sdk-get-font-face (point)) wucuo-double-check-font-faces))
      (let* ((pos (- (point) (length word)))
             (ch (char-before (1- pos))))
        ;; aspell regard symbol as part of word
        ;; @see http://aspell.net/0.61/man-html/Words-With-Symbols-in-Them.html#Words-With-Symbols-in-Them
        ;; @see https://github.com/redguardtoo/emacs.d/issues/892
        (when (and (memq (wucuo-sdk-get-font-face pos) wucuo-double-check-font-faces)
                   (eq (char-before pos) ?')
                   (<= ?a ch)
                   (>= ?z ch))
          (setq typo-p (wucuo-typo-p word)))))
    (not typo-p)))

;;;###autoload
(defun wucuo-generic-check-word-predicate ()
  "Function providing per-mode customization over which words are spell checked.
Returns t to continue checking, nil otherwise."

  (let* ((case-fold-search nil)
         (pos (- (point) 1))
         (current-font-face (and (> pos 0) (wucuo-sdk-get-font-face pos)))
         ;; "(flyspell-mode 1)" loads per major mode predicate anyway
         (mode-predicate (wucuo--get-mode-predicate))
         (font-matched (wucuo--font-matched-p current-font-face))
         subwords
         word
         (rlt t))

    (if wucuo-debug (message "mode-predicate=%s" mode-predicate))
    (if wucuo-debug (message "font-matched=%s, current-font-face=%s" font-matched current-font-face))
    (cond
     ((<= pos 0)
      nil)
     ;; ignore two character word.
     ;; in some major mode, word equals to sub-word
     ((< (length (setq word (save-excursion
                              (goto-char pos)
                              (thing-at-point 'word)))) 2)
      (setq rlt nil))

     ((and mode-predicate (not (funcall mode-predicate)))
      ;; run major mode predicate
      (setq rlt nil))

     ;; should be right after per mode predicate
     ((and wucuo-enable-extra-typo-detection-algorithm-p
           (or (and (wucuo-major-mode-html-p)
                    (not (wucuo-flyspell-html-verify)))
               (and (eq major-mode 'org-mode)
                    (not (wucuo-flyspell-org-verify)))
               (and (eq major-mode 'markdown-mode)
                    (not (markdown-flyspell-check-word-p)))))

      (setq rlt nil))

     ;; only check word with certain fonts
     ((and (not mode-predicate) (not font-matched))
      ;; major mode's predicate might want to manage font face check by itself
      (setq rlt nil))

     ;; handle camel case word
     ((and wucuo-enable-camel-case-algorithm-p
           (setq subwords (wucuo-split-camel-case word))
           (> (length subwords) 1))
      (let* ((s (mapconcat #'wucuo-handle-sub-word subwords " ")))
        (setq rlt (wucuo-check-camel-case-word-predicate s))))

     ((wucuo-aspell-incorrect-typo-p word)
      (setq rlt nil))

     ;; `wucuo-extra-predicate' actually does nothing by default
     (t
      (setq rlt (funcall wucuo-extra-predicate word))))

    (when wucuo-debug
      (message "wucuo-generic-check-word-predicate => word=%s rlt=%s wucuo-extra-predicate=%s subwords=%s"
               word rlt wucuo-extra-predicate subwords))
    rlt))

;;;###autoload
(defun wucuo-create-aspell-personal-dictionary ()
  "Create aspell personal dictionary which is utf-8 encoded plain text file."
  (interactive)
  (with-temp-buffer
    (let* ((file (file-truename (format "~/.aspell.%s.pws" wucuo-aspell-language-to-use))))
      (insert (format "personal_ws-1.1 %s 2\nabcd\ndefg\n" wucuo-aspell-language-to-use))
      (write-file file)
      (message "%s created." file))))

;;;###autoload
(defun wucuo-create-hunspell-personal-dictionary ()
  "Create hunspell personal dictionary which is utf-8 encoded plain text file."
  (interactive)
  (with-temp-buffer
    (let* ((f (file-truename (format "~/.hunspell_%s" wucuo-hunspell-dictionary-base-name))))
      (insert "abcd\ndefg\n")
      (write-file f)
      (message "%s created." f))))

;;;###autoload
(defun wucuo-version ()
  "Output version."
  (message "0.3.2"))

;;;###autoload
(defun wucuo-spell-check-visible-region ()
  "Spell check visible region in current buffer."
  (interactive)
  (let* ((beg (max (point-min) (window-start)))
         (end (min (point-max) (window-end))))
    (when (< (- end beg) wucuo-spell-check-region-max)
      (if wucuo-debug (message "wucuo-spell-check-visible-region called from %s to %s; major-mode=%s" beg end major-mode))
      ;; See https://emacs-china.org/t/flyspell-mode-wucuo-0-2-0/13274/46
      ;; where the performance issue is reported.
      ;; Tested in https://github.com/emacs-mirror/emacs/blob/master/src/xdisp.c
      (font-lock-ensure beg end)
      (flyspell-region beg end))))

(defun wucuo-buffer-windows-visible-p ()
  "Check if current buffer's windows is visible."
  (let* ((win (get-buffer-window (current-buffer))))
    (and win (window-live-p win))))

(defun wucuo-spell-check-internal ()
  "Spell check buffer or internal region."
  ;; work around some old ispell issue on Emacs 27.1
  (unless (boundp 'ispell-menu-map-needed)
    (defvar ispell-menu-map-needed nil))

  ;; hide "Spell Checking ..." message
  (let* ((flyspell-issue-message-flag nil))
    (cond
     ;; check buffer
     ((and (string= wucuo-flyspell-start-mode "normal")
           (< (buffer-size) wucuo-spell-check-buffer-max))
      (if wucuo-debug (message "flyspell-buffer called."))
      ;; `font-lock-ensure' on whole buffer could be slow
      (font-lock-ensure)
      (flyspell-buffer))

     ;; check visible region
     ((string= wucuo-flyspell-start-mode "fast")
      (wucuo-spell-check-visible-region)))))

;;;###autoload
(defun wucuo-spell-check-buffer ()
  "Spell check current buffer."
  (if wucuo-debug (message "wucuo-spell-check-buffer called."))
  (cond
   ((or (null ispell-program-name)
        (not (executable-find ispell-program-name))
        (not (string-match "aspell\\(\\.exe\\)?$\\|hunspell\\(\\.exe\\)?$" ispell-program-name)))
    ;; do nothing, wucuo only works with aspell or hunspell
    (if wucuo-debug (message "aspell/hunspell missing in `ispell-program-name' or not installed.")))

   ((or (not wucuo-timer)
        (> (- (float-time (current-time)) (float-time wucuo-timer))
           wucuo-update-interval))
    ;; start timer if not started yet
    (setq wucuo-timer (current-time))

    (if wucuo-debug (message "wucuo-spell-check-buffer actually happened."))

    (when (and (wucuo-buffer-windows-visible-p)
               (or (null wucuo-spell-check-buffer-predicate)
                   (and (functionp wucuo-spell-check-buffer-predicate)
                        (funcall wucuo-spell-check-buffer-predicate))))
      (wucuo-spell-check-internal)))

   (t
    ;; do nothing, avoid `flyspell-buffer' too often
    (if wucuo-debug (message "wucuo-spell-check-buffer actually skipped.")))))

;;;###autoload
(defun wucuo-start (&optional arg)
  "Turn on wucuo to spell check code.  ARG is ignored."
  (interactive)
  (if wucuo-debug (message "wucuo-start called."))
  (ignore arg)
  (cond
   (wucuo-inherit-flyspell-mode-keybindings
    (wucuo-mode 1))
   (t
    (wucuo-mode-on))))

(defun wucuo-stop ()
  "Turn off wucuo and stop spell checking code."
  (interactive)
  (if wucuo-debug (message "wucuo-stop called."))
  (cond
   (wucuo-inherit-flyspell-mode-keybindings
    (wucuo-mode -1))
   (t
    (wucuo-mode-off))))

(defun wucuo-enhance-flyspell ()
  "Enhance flyspell."
  ;; To be honest, no other major mode can do better than this program
  (setq flyspell-generic-check-word-predicate
        #'wucuo-generic-check-word-predicate)

  ;; work around issue when calling `flyspell-small-region'
  ;; can't show the overlay of error but can't delete overlay
  (setq flyspell-large-region 1))

;;;###autoload
(defun wucuo-aspell-cli-args (&optional run-together)
  "Create arguments for aspell cli.
If RUN-TOGETHER is t, aspell can check camel cased word."
  (let* ((args '("--sug-mode=ultra")))
    ;; "--run-together-min" could NOT be 3, see `check` in "speller_impl.cpp" of aspell code
    ;; The algorithm is not precise.
    ;; Run `echo tasteTableConfig | aspell --lang=en_US -C --run-together-limit=16  --encoding=utf-8 -a` in shell.
    (when run-together
      (cond
       ;; Kevin Atkinson said now aspell supports camel case directly
       ;; https://github.com/redguardtoo/emacs.d/issues/796
       ((string-match-p "--.*camel-case"
                        (shell-command-to-string (concat ispell-program-name " --help")))
        (setq args (append args '("--camel-case"))))

       ;; old aspell uses "--run-together". Please note we are not dependent on this option
       ;; to check camel case word. wucuo is the final solution. This aspell options is just
       ;; some extra check to speed up the whole process.
       (t
        (setq args (append args '("--run-together" "--run-together-limit=16"))))))
    args))

;;;###autoload
(defun wucuo-flyspell-highlight-incorrect-region-hack (orig-func &rest args)
  "Don't mark double words as typo.  ORIG-FUNC and ARGS is part of advice."
  (let* ((poss (nth 2 args)))
    (when (or wucuo-flyspell-check-doublon (not (eq 'doublon poss)))
      (apply orig-func args))))

(with-eval-after-load 'flyspell
  (advice-add 'flyspell-highlight-incorrect-region :around #'wucuo-flyspell-highlight-incorrect-region-hack))

(defun wucuo-goto-next-error ()
  "Go to next error silently."
  (let ((pos (point))
        (max (point-max)))
    (when (and (eq (current-buffer) flyspell-old-buffer-error)
               (eq pos flyspell-old-pos-error))
      (if (= flyspell-old-pos-error max) (goto-char (point-min))
        (forward-word 1))
      (setq pos (point)))
    ;; seek the next error
    (while (and (< pos max)
                (let ((ovs (overlays-at pos))
                      (r '()))
                  (while (and (not r) (consp ovs))
                    (if (flyspell-overlay-p (car ovs))
                        (setq r t)
                      (setq ovs (cdr ovs))))
                  (not r)))
      (setq pos (1+ pos)))
    ;; save the current location for next invocation
    (setq flyspell-old-pos-error pos)
    (setq flyspell-old-buffer-error (current-buffer))
    (goto-char pos)))

;;;###autoload
(defun wucuo-spell-check-file (file &optional kill-emacs-p full-path-p)
  "Spell check FILE and report all typos.
If KILL-EMACS-P is t, kill the Emacs and set exit program code.
If FULL-PATH-P is t, always show typo's file full path.
Return t if there is typo."
  (find-file file)
  ;; should set `flyspell-generic-check-word-predicate' after major mode is loaded
  (wucuo-enhance-flyspell)

  (font-lock-ensure)
  (let* ((wucuo-flyspell-start-mode "normal")
         typo-p)
    (wucuo-spell-check-internal)
    ;; report all errors
    (goto-char (point-min))
    (wucuo-goto-next-error)
    (while (< (point) (1- (point-max)))
      (setq typo-p t)
      (message "%s:%s: typo '%s' at %s is found"
               (if full-path-p (file-truename file) file)
               (count-lines (point-min) (point))
               (thing-at-point 'word)
               (point))
      (wucuo-goto-next-error))
    (when (and typo-p kill-emacs-p)
      (kill-emacs 1))
    typo-p))

;;;###autoload
(defun wucuo-find-file-predicate  (file dir)
  "True if FILE does match `wucuo-find-file-regexp'.
And FILE does not match `wucuo-exclude-file-regexp'.
DIR is the directory containing FILE."
  (and (not (file-directory-p (expand-file-name file dir)))
       (not (and wucuo-exclude-file-regexp
                 (string-match wucuo-exclude-file-regexp file)))
       (string-match wucuo-find-file-regexp file)))

;;;###autoload
(defun wucuo-find-directory-predicate  (dir parent)
  "True if DIR is not a dot file, and not a symlink.
And DIR does not match `wucuo-exclude-directories'.
PARENT is the parent directory of DIR."
  ;; Skip current and parent directories
  (not (or (string= dir ".")
           (string= dir "..")
           (member dir wucuo-exclude-directories)
           ;; Skip directories which are symlinks
           ;; Easy way to circumvent recursive loops
           (file-symlink-p (expand-file-name dir parent)))))

;;;###autoload
(defun wucuo-spell-check-directory (directory &optional kill-emacs-p full-path-p)
  "Spell check DIRECTORY and report all typos.
If KILL-EMACS-P is t, kill the Emacs and set exit program code.
If FULL-PATH-P is t, always show typo's file full path."
  (let* ((files (find-lisp-find-files-internal directory
                                               #'wucuo-find-file-predicate
                                               #'wucuo-find-directory-predicate))
         (count (length files))
         (i 1)
         typo-p)

    (dolist (f files)
      (when wucuo-debug
        (message "checking file %s %s/%s"  f i count)
        (setq i (1+ i)))

      (when (wucuo-spell-check-file f nil full-path-p)
        (setq typo-p t)))
    (when (and typo-p kill-emacs-p)
      (kill-emacs 1))))

(defun wucuo-mode-on ()
  "Turn Wucuo mode on."
  (cond
   (flyspell-mode
    (message "Please turn off `flyspell-mode' and `flyspell-prog-mode' before wucuo starts!"))
   (t
    (wucuo-enhance-flyspell)
    (add-hook 'after-save-hook #'wucuo-spell-check-buffer nil t))))

(defun wucuo-mode-off ()
  "Turn Wucuo mode on."

  ;; {{ copied from `flyspell-mode-off'
  (flyspell-delete-all-overlays)
  (setq flyspell-pre-buffer nil)
  (setq flyspell-pre-point  nil)
  ;; }}

  (remove-hook 'after-save-hook #'wucuo-spell-check-buffer t))

(define-minor-mode wucuo-mode
  "Toggle spell checking (Wucuo mode).
With a prefix argument ARG, enable Flyspell mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil.

Wucuo mode is a buffer-local minor mode.  When enabled, it
spawns a single Ispell process and checks each word.  The default
flyspell behavior is to highlight incorrect words.

Remark:
`wucuo-mode' uses `flyspell' and `flyspell-mode-map'.
So all Flyspell setup and key bindings are valid."
  :lighter flyspell-mode-line-string
  :keymap flyspell-mode-map
  :group 'wucuo
  (cond
   (wucuo-mode
    (condition-case err
        (wucuo-mode-on)
      (error (message "Error enabling Flyspell mode:\n%s" (cdr err))
             (wucuo-mode -1))))
   (t
    (wucuo-mode-off))))

(provide 'wucuo)
;;; wucuo.el ends here
