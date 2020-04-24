;;; inform.el --- Symbol links in Info buffers to their help documentation  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  H. Dieter Wilhelm

;; Author: H. Dieter Wilhelm <dieter@duenenhof-wilhelm.de>
;; Keywords: help, docs, convenience
;; Maintainer: H. Dieter Wilhelm
;; Version: 20.5.0
;; URL: https://github.com/dieter-wilhelm/inform

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This library provides links for symbols (functions, variables, ...)
;; within texinfo (*info*) buffers to their help documentation.

;;; Todo:

;; Update documentation strings

;; Back / Forward button in help buffer - back to info buffer or
;; remain in help mode?

;;; Code:

(require 'button)
(require 'cl-lib)

;; Button types

(define-button-type 'Inform-xref
  'link t			   ; for Inform-next-reference-or-link
  'follow-link t
  'action #'Inform-button-action)

(define-button-type 'Inform-function
  :supertype 'Inform-xref
  'Inform-function 'describe-function
  'Inform-echo (purecopy "mouse-2, RET: describe this function"))

(define-button-type 'Inform-variable
  :supertype 'Inform-xref
  'Inform-function 'describe-variable
  'Inform-echo (purecopy "mouse-2, RET: describe this variable"))

(define-button-type 'Inform-face
  :supertype 'Inform-xref
  'Inform-function 'describe-face
  'Inform-echo (purecopy "mouse-2, RET: describe this face"))

(define-button-type 'Inform-symbol
  :supertype 'Inform-xref
  'Inform-function #'describe-symbol
  'Inform-echo (purecopy "mouse-2, RET: describe this symbol"))

(define-button-type 'Inform-function-def
  :supertype 'Inform-xref
  'Inform-function (lambda (fun &optional file type)
                   (or file
                       (setq file (find-lisp-object-file-name fun type)))
                   (if (not file)
                       (message "Unable to find defining file")
                     (require 'find-func)
                     (when (eq file 'C-source)
                       (setq file
                             (help-C-file-name (indirect-function fun) 'fun)))
                     ;; Don't use find-function-noselect because it follows
                     ;; aliases (which fails for built-in functions).
                     (let ((location
                            (find-function-search-for-symbol fun type file)))
                       (pop-to-buffer (car location))
                       (run-hooks 'find-function-after-hook)
                       (if (cdr location)
                           (goto-char (cdr location))
                         (message "Unable to find location in file")))))
  'Inform-echo (purecopy "mouse-2, RET: find function's definition"))

;; Functions

(defun Inform-button-action (button)
  "Call BUTTON's help function."
  (Inform-do-xref nil
                (button-get button 'Inform-function)
                (button-get button 'Inform-args)))

;; (defvar help-xref-following)
;; (defvar Inform-xref-following nil
;;   "Non-nil when following a help cross-reference.")

(defun Inform-do-xref (_pos function args)
  "Call the help cross-reference function FUNCTION with args ARGS.
Things are set up properly so that the resulting `help-buffer' has
a proper [back] button."
  ;; There is a reference at point.  Follow it.
  (let ((help-xref-following nil))
    (apply function (if (eq function 'info)
                        (append args (list (generate-new-buffer-name "*info*"))) args))))

(defun Inform-xref-button (match-number type &rest args)
  "Make a hyperlink for cross-reference text previously matched.
MATCH-NUMBER is the subexpression of interest in the last matched
regexp.  TYPE is the type of button to use.  Any remaining arguments are
passed to the button's help-function when it is invoked.
See `help-make-xrefs' Don't forget ARGS." ; -TODO-
  ;; Don't mung properties we've added specially in some instances.
  (unless (button-at (match-beginning match-number))
    (message "Creating button: %s." args)
    (make-text-button (match-beginning match-number)
                      (match-end match-number)
                      'type type 'Inform-args args)))

(defconst Inform-xref-symbol-regexp
  (purecopy (concat "\\(\\<\\(\\(variable\\|option\\)\\|"  ; Link to var
                    "\\(function\\|command\\|call\\)\\|"   ; Link to function
                    "\\(face\\)\\|"			   ; Link to face
                    "\\(symbol\\|program\\|property\\)\\|" ; Don't link
                    "\\(source \\(?:code \\)?\\(?:of\\|for\\)\\)\\)"
                    "[ \t\n]+\\)?"
                    ;; Note starting with word-syntax character:
                    "['`‘]\\(\\sw\\(\\sw\\|\\s_\\)+\\|`\\)['’]"))
  "Regexp matching doc string references to symbols.

The words preceding the quoted symbol can be used in doc strings to
distinguish references to variables, functions and symbols.")

(defvar describe-symbol-backends
  `((nil ,#'fboundp ,(lambda (s _b _f) (describe-function s)))
    (nil
     ,(lambda (symbol)
        (or (and (boundp symbol) (not (keywordp symbol)))
            (get symbol 'variable-documentation)))
     ,#'describe-variable)
    ("face" ,#'facep ,(lambda (s _b _f) (describe-face s))))
  "List of providers of information about symbols.
Each element has the form (NAME TESTFUN DESCFUN) where:
  NAME is a string naming a category of object, such as \"type\" or \"face\".
  TESTFUN is a predicate which takes a symbol and returns non-nil if the
    symbol is such an object.
  DESCFUN is a function which takes three arguments (a symbol, a buffer,
    and a frame), inserts the description of that symbol in the current buffer
    and returns that text as well.")

(defun Inform-make-xrefs (&optional buffer)
  "Parse and hyperlink documentation cross-references in the given BUFFER.

Find cross-reference information in a buffer and activate such cross
references for selection with `help-follow'.  Cross-references have
the canonical form `...'  and the type of reference may be
disambiguated by the preceding word(s) used in
`help-xref-symbol-regexp'.  Faces only get cross-referenced if
preceded or followed by the word `face'.  Variables without
variable documentation do not get cross-referenced, unless
preceded by the word `variable' or `option'.

If the variable `help-xref-mule-regexp' is non-nil, find also
cross-reference information related to multilingual environment
\(e.g., coding-systems).  This variable is also used to disambiguate
the type of reference as the same way as `help-xref-symbol-regexp'.

A special reference `back' is made to return back through a stack of
help buffers.  Variable `help-back-label' specifies the text for
that."
  (interactive "b")
  (message "Creating xrefs..")
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (goto-char (point-min))
      ;; Skip the header-type info, though it might be useful to parse
      ;; it at some stage (e.g. "function in `library'").
      ;;      (forward-paragraph)
      (let ((old-modified (buffer-modified-p)))
        (let ((stab (syntax-table))
              (case-fold-search t)
              (inhibit-read-only t))
          (set-syntax-table emacs-lisp-mode-syntax-table)
          ;; The following should probably be abstracted out.
          (unwind-protect
              (progn
                ;; ;; Info references
                ;; (save-excursion
                ;;   (while (re-search-forward help-xref-info-regexp nil t)
                ;;     (let ((data (match-string 2)))
                ;;       (save-match-data
                ;;         (unless (string-match "^([^)]+)" data)
                ;;           (setq data (concat "(emacs)" data)))
                ;;      (setq data ;; possible newlines if para filled
                ;;            (replace-regexp-in-string "[ \t\n]+" " " data t t)))
                ;;       (help-xref-button 2 'help-info data))))
                ;; ;; URLs
                ;; (save-excursion
                ;;   (while (re-search-forward help-xref-url-regexp nil t)
                ;;     (let ((data (match-string 1)))
                ;;       (help-xref-button 1 'help-url data))))
                ;; ;; Mule related keywords.  Do this before trying
                ;; ;; `help-xref-symbol-regexp' because some of Mule
                ;; ;; keywords have variable or function definitions.
                ;; (if help-xref-mule-regexp
                ;;     (save-excursion
                ;;       (while (re-search-forward help-xref-mule-regexp nil t)
                ;;         (let* ((data (match-string 7))
                ;;                (sym (intern-soft data)))
                ;;           (cond
                ;;            ((match-string 3) ; coding system
                ;;             (and sym (coding-system-p sym)
                ;;                  (help-xref-button 6 'help-coding-system sym)))
                ;;            ((match-string 4) ; input method
                ;;             (and (assoc data input-method-alist)
                ;;                  (help-xref-button 7 'help-input-method data)))
                ;;            ((or (match-string 5) (match-string 6)) ; charset
                ;;             (and sym (charsetp sym)
                ;;                  (help-xref-button 7 'help-character-set sym)))
                ;;            ((assoc data input-method-alist)
                ;;             (help-xref-button 7 'help-input-method data))
                ;;            ((and sym (coding-system-p sym))
                ;;             (help-xref-button 7 'help-coding-system sym))
                ;;            ((and sym (charsetp sym))
                ;;             (help-xref-button 7 'help-character-set sym)))))))

                ;; Quoted symbols
                (save-excursion
                  (while (re-search-forward Inform-xref-symbol-regexp nil t)
                    (let* ((data (match-string 8))
                           (sym (intern-soft data)))
                      (if sym
                          (cond
                           ((match-string 3) ; `variable' &c
                            (and (or (boundp sym) ; `variable' doesn't ensure
                                        ; it's actually bound
                                     (get sym 'variable-documentation))
                                 (Inform-xref-button 8 'Inform-variable sym)))
                           ((match-string 4) ; `function' &c
                            (and (fboundp sym) ; similarly
                                 (Inform-xref-button 8 'Inform-function sym)))
                           ((match-string 5) ; `face'
                            (and (facep sym)
                                 (Inform-xref-button 8 'Inform-face sym)))
                           ((match-string 6)) ; nothing for `symbol'
                           ((match-string 7)
                            (Inform-xref-button 8 'Inform-function-def sym))
                           ((cl-some (lambda (x) (funcall (nth 1 x) sym))
                                     describe-symbol-backends)
                            (Inform-xref-button 8 'Inform-symbol sym))
                           )))))
                ;; An obvious case of a key substitution:
                ;; (save-excursion
                ;;   (while (re-search-forward
                ;;           ;; Assume command name is only word and symbol
                ;;           ;; characters to get things like `use M-x foo->bar'.
                ;;           ;; Command required to end with word constituent
                ;;           ;; to avoid `.' at end of a sentence.
                ;;           "\\<M-x\\s-+\\(\\sw\\(\\sw\\|\\s_\\)*\\sw\\)" nil t)
                ;;     (let ((sym (intern-soft (match-string 1))))
                ;;       (if (fboundp sym)
                ;;           (help-xref-button 1 'help-function sym)))))
                ;; ;; Look for commands in whole keymap substitutions:
                ;; (save-excursion
                ;;   ;; Make sure to find the first keymap.
                ;;   (goto-char (point-min))
                ;;   ;; Find a header and the column at which the command
                ;;   ;; name will be found.

                ;;   ;; If the keymap substitution isn't the last thing in
                ;;   ;; the doc string, and if there is anything on the same
                ;;   ;; line after it, this code won't recognize the end of it.
                ;;   (while (re-search-forward "^key +binding\n\\(-+ +\\)-+\n\n"
                ;;                             nil t)
                ;;     (let ((col (- (match-end 1) (match-beginning 1))))
                ;;       (while
                ;;           (and (not (eobp))
                ;;                ;; Stop at a pair of blank lines.
                ;;                (not (looking-at-p "\n\\s-*\n")))
                ;;         ;; Skip a single blank line.
                ;;         (and (eolp) (forward-line))
                ;;         (end-of-line)
                ;;         (skip-chars-backward "^ \t\n")
                ;;         (if (and (>= (current-column) col)
                ;;                  (looking-at "\\(\\sw\\|\\s_\\)+$"))
                ;;             (let ((sym (intern-soft (match-string 0))))
                ;;               (if (fboundp sym)
                ;;                   (help-xref-button 0 'help-function sym))))
                ;;         (forward-line))))))
                )
            (set-syntax-table stab))
          ;; Delete extraneous newlines at the end of the docstring
          ;; (goto-char (point-max))
          ;; (while (and (not (bobp)) (bolp))
          ;;   (delete-char -1))
          ;; (insert "\n")
          ;; (when (or help-xref-stack help-xref-forward-stack)
          ;;   (insert "\n"))
          ;; ;; Make a back-reference in this buffer if appropriate.
          ;; (when help-xref-stack
          ;;   (help-insert-xref-button help-back-label 'help-back
          ;;                            (current-buffer)))
          ;; ;; Make a forward-reference in this buffer if appropriate.
          ;; (when help-xref-forward-stack
          ;;   (when help-xref-stack
          ;;     (insert "\t"))
          ;;   (help-insert-xref-button help-forward-label 'help-forward
          ;;                            (current-buffer)))
          ;; (when (or help-xref-stack help-xref-forward-stack)
          ;;   (insert "\n")))
        (set-buffer-modified-p old-modified))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide 'inform)
;;; inform.el ends here

;; Local Variables:
;; mode: outline-minor
;; indicate-empty-lines: t
;; show-trailing-whitespace: t
;; word-wrap: t
;; time-stamp-active: t
;; time-stamp-format: "%:y-%02m-%02d"
;; End: