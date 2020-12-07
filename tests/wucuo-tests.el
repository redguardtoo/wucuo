;;; wucuo-tests.el ---  unit tests for wucuo -*- coding: utf-8 -*-

;; Author: Chen Bin <chenbin DOT sh AT gmail DOT com>

;;; License:

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

(require 'ert)
(require 'wucuo)

(ert-deftest wucuo-test-flyspell-buffer ()
  (should (executable-find "aspell"))
  (with-temp-buffer
    (insert "// helle world\n"
            "console.log('hello worlde');")
    (js-mode)
    (font-lock-ensure)

    ;; check whole buffer
    (let* ((wucuo-flyspell-start-mode "normal"))
      (wucuo-spell-check-internal))
    (goto-char (point-min))
    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-comment-face"))
    (should (wucuo--font-matched-p (wucuo-sdk-get-font-face (point))))
    (should (string= "helle" (thing-at-point 'word)))

    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-string-face"))
    (should (wucuo--font-matched-p (wucuo-sdk-get-font-face (point))))
    (should (string= "worlde" (thing-at-point 'word)))

    ;; end of errors
    (flyspell-goto-next-error)
    (should (null (thing-at-point 'word)))

    (should (eq major-mode 'js-mode))))

(ert-deftest wucuo-test-check-function-variable ()
  (should (executable-find "aspell"))
  (with-temp-buffer
    (insert "function myfun () {\n"
            " let typoHelle = 3;\n"
            " let correctVariable = 4;\n"
            " let correcVariable = 5;\n"
            " return typoHelle + correctVariable + correcVariable;;\n"
            "}\n")
    (js-mode)
    (font-lock-ensure)

    (wucuo-enhance-flyspell)
    ;; check whole buffer
    (let* ((wucuo-flyspell-start-mode "normal"))
      (wucuo-spell-check-internal))

    (goto-char (point-min))

    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-function-name-face"))
    (should (wucuo--font-matched-p (wucuo-sdk-get-font-face (point))))
    (should (string= "myfun" (thing-at-point 'word)))

    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-variable-name-face"))
    (should (wucuo--font-matched-p (wucuo-sdk-get-font-face (point))))
    (should (string= "typoHelle" (thing-at-point 'word)))

    ;; Please note correct "correctVar" is right camel-cased name
    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-variable-name-face"))
    (should (wucuo--font-matched-p (wucuo-sdk-get-font-face (point))))
    (should (string= "correcVariable" (thing-at-point 'word)))

    ;; end of errors
    (flyspell-goto-next-error)
    (should (null (thing-at-point 'word)))

    (should (eq major-mode 'js-mode))))

(ert-deftest wucuo-test-check-api ()
  (should (wucuo-typo-p "helle"))
  (should (not (wucuo-typo-p "hello"))))

(ert-deftest wucuo-test-aspell-workaround ()
  (with-temp-buffer
    (insert "print(f'hello test lex helle')\n")
    (python-mode)
    (font-lock-ensure)

    (wucuo-enhance-flyspell)
    ;; check whole buffer
    (let* ((wucuo-flyspell-start-mode "normal"))
      (wucuo-spell-check-internal))

    (goto-char (point-min))

    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-string-face"))
    (should (string= "lex" (thing-at-point 'word)))

    (flyspell-goto-next-error)
    (should (string= (wucuo-current-font-face) "font-lock-string-face"))
    (should (string= "helle" (thing-at-point 'word)))

    (should (eq major-mode 'python-mode))))

(ert-run-tests-batch-and-exit)
;;; wucuo-tests.el ends here
