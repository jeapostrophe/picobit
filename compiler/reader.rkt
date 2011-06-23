#lang racket

(require (only-in unstable/port read-all)
         racket/runtime-path
         srfi/4)

(provide read-file)

;; at this point, the #u or #u8(...) has already been seen
(define (read-u8vector port)
  (unless (and (equal? (read-char port) #\8)
               (equal? (read-char port) #\())
    (error "bad byte vector syntax"))
  (let ([s (open-output-string)])
    (let loop ([c (read-char port)])
      ;; parse until the closing paren
      (cond [(eof-object? c)
             (error "bad byte vector syntax")]
            [(not (equal? c #\)))
             (display c s)
             (loop (read-char port))]
            [else
             ;; we saw the closing paren, we're done
             (let ([contents (regexp-split #px"[[:space:]]+"
                                           (get-output-string s))])
               (list->u8vector
                (map string->number contents)))]))))

;; u8vector literals are not natively supported by Racket
(define u8vector-readtable
  (make-readtable
   (current-readtable)
   #\u
   'dispatch-macro
   (case-lambda
     [(char port) ; read
      (read-u8vector port)]
     [(char port src line col pos) ; read-syntax
      (read-u8vector port)])))

(define (expand-includes exprs)
  (map (lambda (e)
         (if (eq? (car e) 'include)
             (cons 'begin
                   (expand-includes
                    (with-input-from-file (cadr e) read-all)))
             e))
       exprs))

(define-runtime-path compiler-dir ".")

(define (read-file filename)
  (parameterize ([current-readtable u8vector-readtable])
    (let ([library
           (with-input-from-file (build-path compiler-dir "library.scm")
             read-all)])
      (expand-includes
       (append library
               (with-input-from-file filename read-all))))))