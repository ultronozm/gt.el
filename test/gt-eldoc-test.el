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
           (gt-current-translator gt-default-translator)
           (gt-current-command 'gt-translate)
           result)
      ;; A previously used default translator saves its renderer here.
      (gt-reset gt-default-translator)
      (gt-eldoc-mode 1)
      (should (gt-eldoc-documentation-function
               (lambda (text &rest _) (setq result text))))
      (should (equal result "HELLO"))
      (should (eq (oref gt-default-translator _render) original-render))
      (should (eq gt-current-translator gt-default-translator))
      (should (eq gt-current-command 'gt-translate)))))

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
      (let (old-result new-result)
        (gt-eldoc-documentation-function
         (lambda (text &rest _) (setq old-result text)))
        (gt-eldoc-documentation-function
         (lambda (text &rest _) (setq new-result text)))
        (let ((deadline (+ (float-time) 0.2)))
          (while (< (float-time) deadline)
            (accept-process-output nil 0.01)))
        (should-not old-result)
        (should (equal new-result "HELLO")))
      (setq result nil)
      (gt-eldoc-documentation-function
       (lambda (text &rest _) (setq result text)))
      (save-excursion (goto-char (point-max)) (insert "!"))
      (let ((deadline (+ (float-time) 0.2)))
        (while (< (float-time) deadline)
          (accept-process-output nil 0.01)))
      (should-not result)
      (gt-eldoc-documentation-function
       (lambda (text &rest _) (setq result text)))
      (gt-eldoc-mode -1)
      (let ((deadline (+ (float-time) 0.2)))
        (while (< (float-time) deadline)
          (accept-process-output nil 0.01)))
      (should-not result))))

(ert-deftest gt-eldoc-uses-first-preset-when-default-is-nil ()
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-min))
    (let* ((gt-default-translator nil)
           (preset (gt-translator
                    :taker (gt-taker :text 'word :langs '(en da) :pick nil)
                    :engines (gt-echo-engine
                              :do (lambda (text) (mapcar #'upcase text)))))
           (gt-preset-translators (lambda () (list (cons 'default preset))))
           result)
      (gt-eldoc-mode 1)
      (should (gt-eldoc-documentation-function
               (lambda (text &rest _) (setq result text))))
      (should (equal result "HELLO"))
      (should-not gt-default-translator)
      (should-not (slot-boundp preset '_render)))))

(ert-deftest gt-eldoc-completes-configured-streaming-engine ()
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-min))
    (let* ((engine (gt-chatgpt-engine :stream t))
           (gt-default-translator
            (gt-translator :taker (gt-taker :text 'word :langs '(en da) :pick nil)
                           :engines (lambda () (list engine))))
          (gt-chatgpt-streaming-finished-hook nil)
          requested-stream result)
      (cl-letf (((symbol-function 'gt-resolve-key) (lambda (_) "offline"))
                ((symbol-function 'gt-chatgpt-send)
                 (lambda (_prompt &rest args)
                   (setq requested-stream (plist-get args :stream))
                   (if requested-stream
                       (let ((peek pdd-peek))
                         (pdd-delay 0.01
                           (lambda ()
                             (with-temp-buffer
                               (insert "data: {\"choices\":[{\"delta\":{\"content\":\"HELLO\"},\"finish_reason\":null}]}\n\n"
                                       "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n")
                               (goto-char (point-min))
                               (funcall peek))
                             t)))
                     ;; A renderer may choose complete responses for ElDoc
                     ;; without mutating the user's configured engine.
                     (pdd-delay 0.01
                       '((choices . [((message . ((content . "HELLO"))))])))))))
        ;; Exercise both the engine factory and the translator's saved slots.
        (gt-reset gt-default-translator)
        (gt-eldoc-mode 1)
        (should (gt-eldoc-documentation-function
                 (lambda (text &rest _) (setq result text))))
        (let ((deadline (+ (float-time) 0.2)))
          (while (< (float-time) deadline)
            (accept-process-output nil 0.01)))
        (should (equal result "HELLO"))
        (should-not requested-stream)
        (should (oref engine stream))))))
