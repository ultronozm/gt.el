;;; -*- lexical-binding: t; -*-
;;; gt-eldoc.el --- Translation results through ElDoc

;; Copyright (C) 2026 Paul D. Nelson
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Enable `gt-eldoc-mode' to translate at point using the taker and engines
;; of `gt-default-translator', displaying results through ElDoc.

;;; Code:

(require 'gt)
(require 'eldoc)

(defclass gt-eldoc-render (gt-render)
  ((callback :initarg :callback :type function))
  "Pass completed translations to an ElDoc callback.")

(cl-defmethod gt-init :around ((render gt-eldoc-render) translator)
  ;; Idle documentation should not announce each request in the echo area.
  (let ((inhibit-message t))
    (cl-call-next-method render translator)))

(cl-defmethod gt-output ((render gt-eldoc-render) (translator gt-translator))
  (when (= (oref translator state) 3)
    (let ((results
           (cl-loop for item in (gt-extract-data render translator)
                    when (= (plist-get item :state) 2)
                    append (ensure-list (plist-get item :result)))))
      (funcall (oref render callback)
               (and results (string-join results "\n\n"))
               :face 'font-lock-doc-face))))

(defvar-local gt-eldoc--request nil)
(defvar gt-eldoc-mode)

(defun gt-eldoc-documentation-function (callback)
  "Translate at point and pass the result to ElDoc CALLBACK."
  (when gt-default-translator
    (condition-case nil
        (let* ((buffer (current-buffer))
               (position (point))
               (tick (buffer-chars-modified-tick))
               (request (setq gt-eldoc--request (list nil)))
               ;; Component constructors are cached by printed arguments.
               ;; Clone a prototype so each request keeps its own callback.
               (render
                (clone (gt-eldoc-render :callback #'ignore)
                 :callback
                 (lambda (&rest args)
                   (when (buffer-live-p buffer)
                     (with-current-buffer buffer
                       (when (and gt-eldoc-mode
                                  (eq request gt-eldoc--request)
                                  (= position (point))
                                  (= tick (buffer-chars-modified-tick)))
                         (apply callback args)))))))
               (translator (clone gt-default-translator :render render)))
          ;; Translators previously used by `gt-start' retain their initial
          ;; components here; `gt-reset' restores them at the next request.
          (when (slot-boundp translator '_render)
            (oset translator _render render))
          (gt-start translator)
          t)
      (user-error nil))))

;;;###autoload
(define-minor-mode gt-eldoc-mode
  "Translate at point through ElDoc using `gt-default-translator'."
  :lighter " GT-ElDoc"
  (if gt-eldoc-mode
      (progn
        (add-hook 'eldoc-documentation-functions
                  #'gt-eldoc-documentation-function nil t)
        (eldoc-mode 1))
    (setq gt-eldoc--request nil)
    (remove-hook 'eldoc-documentation-functions
                 #'gt-eldoc-documentation-function t)))

(provide 'gt-eldoc)
;;; gt-eldoc.el ends here
