;;; -*- lexical-binding: t; -*-
(require 'ert)
(require 'gt-eldoc)

(ert-deftest gt-eldoc-used-translator-keeps-its-normal-renderer ()
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-min))
    (let* ((original-render (gt-buffer-render))
           (gt-default-translator
            (gt-translator :taker (gt-taker :text 'word :langs '(en da) :pick nil)
                           :engines (gt-echo-engine :do (lambda (text) (mapcar #'upcase text)))
                           :render original-render))
           result)
      ;; A previously used default translator saves its renderer here.
      (gt-reset gt-default-translator)
      (gt-eldoc-mode 1)
      (should (gt-eldoc-documentation-function
               (lambda (text &rest _) (setq result text))))
      (should (equal result "HELLO"))
      (should (eq (oref gt-default-translator _render) original-render)))))

(ert-deftest gt-eldoc-discards-stale-asynchronous-results ()
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-min))
    (let ((gt-default-translator
           (gt-translator :taker (gt-taker :text 'word :langs '(en da) :pick nil)
                          :engines (gt-echo-engine
                                    :do (lambda (text)
                                          (pdd-delay 0.01 (mapcar #'upcase text))))))
          result)
      (gt-eldoc-mode 1)
      (gt-eldoc-documentation-function
       (lambda (text &rest _) (setq result text)))
      (goto-char (point-max))
      (let ((deadline (+ (float-time) 0.2)))
        (while (< (float-time) deadline)
          (accept-process-output nil 0.01)))
      (should-not result)
      (goto-char (point-min))
      (gt-eldoc-documentation-function
       (lambda (text &rest _) (setq result text)))
      (let ((deadline (+ (float-time) 0.2)))
        (while (< (float-time) deadline)
          (accept-process-output nil 0.01)))
      (should (equal result "HELLO"))
      (setq result nil)
      (gt-eldoc-documentation-function
       (lambda (text &rest _) (setq result text)))
      (gt-eldoc-mode -1)
      (let ((deadline (+ (float-time) 0.2)))
        (while (< (float-time) deadline)
          (accept-process-output nil 0.01)))
      (should-not result))))
