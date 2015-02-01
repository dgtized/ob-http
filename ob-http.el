(require 'org)
(require 'ob)
(require 's)
(require 'json)
(require 'http-mode)

(defgroup ob-http nil
  "org-mode blocks for http request"
  :group 'org)

(defcustom ob-http:max-time 10
  "maximum time in seconds that you allow the whole operation to take"
  :group 'ob-http
  :type 'integer)

(defstruct ob-http/request method url headers body)

(defun ob-http/parse-input (input)
  (let* ((headers-body (ob-http/split-header-body input))
         (headers (s-split-up-to "\\(\r\n\\|[\n\r]\\)" (car headers-body) 1))
         (method-url (split-string (car  headers) " ")))
    (make-ob-http/request
     :method (car method-url)
     :url (cadr method-url)
     :headers (if (cadr headers) (s-lines (cadr headers)))
     :body (cadr headers-body))))

(defun ob-http/split-header-body (input)
  (s-split-up-to "\\(\r\n\\|[\n\r]\\)[ \t]*\\1" input 1))

(defun ob-http/pretty-json (str)
  (if (executable-find "jq")
      (with-temp-buffer
        (insert str)
        (shell-command-on-region (point-min) (point-max) "jq -r ." nil 't)
        (buffer-string))
    (with-temp-buffer
      (insert str)
      (json-pretty-print-buffer)
      (buffer-string))))

(defun parse-header (line)
  (let ((key-value (s-split-up-to ": " line 1)))
    `(,(s-downcase (car key-value)) . ,(cadr key-value))))

(defun parse-content-type (content-type)
  (if (s-contains? "json" content-type) "json" nil))

(defun ob-http/pretty (str content-type)
  (let ((type (if content-type (parse-content-type content-type) "json")))
    (cond ((string= "json" type) (ob-http/pretty-json str)))))

(defun org-babel-execute:http (body params)
  (let* ((req (ob-http/parse-input body))
         (proxy (cdr (assoc :proxy params)))
         (pretty (assoc :pretty params))
         (pretty-format (if pretty (cdr pretty)))
         (cookie-jar (cdr (assoc :cookie-jar params)))
         (cookie (cdr (assoc :cookie params)))
         (max-time (cdr (assoc :max-time params)))
         (body (ob-http/request-body req))
         (cmd (s-format "curl -is ${proxy} ${method} ${headers} ${cookie-jar} ${cookie} ${body} \"${url}\" --max-time ${max-time}" 'aget
                        `(("proxy" . ,(if proxy (format "-x %s" proxy) ""))
                          ("method" . ,(let ((method (ob-http/request-method req)))
                                         (if (string= "HEAD" method) "-I" (format "-X %s" method))))
                          ("headers" . ,(mapconcat (lambda (x) (format " -H \"%s\"" x))
                                                   (ob-http/request-headers req) ""))
                          ("body" . ,(if (s-present? body)
                                         (let ((tmp (org-babel-temp-file "http-")))
                                           (with-temp-file tmp (insert body))
                                           (format "-d @\"%s\"" tmp))
                                       ""))
                          ("url" . ,(ob-http/request-url req))
                          ("cookie-jar" . ,(if cookie-jar (format "--cookie-jar %s" cookie-jar) ""))
                          ("cookie" . ,(if cookie (format "--cookie %s" cookie) ""))
                          ("max-time" . ,(int-to-string (or max-time ob-http:max-time))))))
         (result (shell-command-to-string cmd))
         (header-body (ob-http/split-header-body result))
         (result-headers (mapcar 'parse-header (s-lines (car header-body))))
         (result-body (cadr header-body)))
    (message cmd)
    (if pretty
        (ob-http/pretty result-body (or (cdr pretty)
                                        (cdr (assoc "content-type" result-headers))))
      result)))

(provide 'ob-http)
