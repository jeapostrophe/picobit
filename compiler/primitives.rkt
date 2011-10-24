#lang racket

(require racket/mpair unstable/sequence racket/syntax)
(require srfi/4)
(require "env.rkt"
         "ast.rkt" "front-end.rkt") ; to build the eta-expansions

;-----------------------------------------------------------------------------

(provide global-env)
(define global-env (mlist))

(provide primitive-encodings)
(define primitive-encodings '())


(define-syntax define-primitive
  (syntax-rules ()
    [(define-primitive name nargs encoding)
     (define-primitive name nargs encoding #:uns-res? #f)]
    [(define-primitive name nargs encoding #:unspecified-result)
     (define-primitive name nargs encoding #:uns-res? #t)]
    [(define-primitive name nargs encoding #:uns-res? uns?)
     (let* ([prim (make-primitive nargs #f #f uns?)]
            [var  (make-primitive-var #'name prim)])
       ;; eta-expansion, for higher-order uses
       (set-primitive-eta-expansion! prim (create-eta-expansion var nargs))
       (set! global-env (mcons var global-env))
       (set! primitive-encodings
             (dict-set primitive-encodings 'name encoding)))]))

(define (create-eta-expansion prim-var nargs)
  ;; We create AST nodes directly. Looks a lot like the parsing of lambdas.
  (define r
    (make-prc #f '() '() #f #f)) ; parent children params rest? entry-label
  (define ids     (build-list nargs (lambda (x) (generate-temporary))))
  (define new-env (env-extend global-env ids r))
  (define args    (for/list ([id (in-list ids)]) (env-lookup new-env id)))
  (define op      (create-ref prim-var))
  (define body    (make-call r (cons op (map create-ref args))))
  (fix-children-parent! body)
  (set-prc-params!    r args)
  (set-node-children! r (list body))
  ;; hidden. you need to know it to get it
  (define eta-id  (generate-temporary (var-id prim-var)))
  (define eta-var (make-global-var eta-id r))
  (define def     (make-def #f (list r) eta-var))
  (add-extra-code def)
  eta-var)

(include "gen.primitives.rkt")


;; Since constant folding is a compiler-only concept, it doesn't make
;; much sense to add folders to primitives in the VM, where primitives
;; are defined.
;; Instead, we add the constant folders post-facto. This requires that
;; the foldable primitives actually be defined, though. Since folding
;; is used for "essential" primitives, that shouldn't be an issue.

(define (add-constant-folder name folder)
  (define prim (var-primitive (env-lookup global-env name)))
  (set-primitive-constant-folder! prim folder))

(define folders
  `((,#'number?           . ,number?)
    (,#'#%+               . ,+)
    (,#'#%-               . ,-)
    (,#'#%mul-non-neg     . ,*)
    (,#'#%div-non-neg     . ,quotient)
    (,#'#%rem-non-neg     . ,remainder)
    (,#'=                 . ,=)
    (,#'<                 . ,<)
    (,#'>                 . ,>)
    (,#'pair?             . ,pair?)
    (,#'car               . ,car)
    (,#'cdr               . ,cdr)
    (,#'null?             . ,null?)
    (,#'eq?               . ,eq?)
    (,#'not               . ,not)
    (,#'symbol?           . ,symbol?)
    (,#'string?           . ,string?)
    (,#'string->list      . ,string->list)
    (,#'list->string      . ,list->string)
    (,#'u8vector-ref      . ,u8vector-ref)
    (,#'u8vector?         . ,u8vector?)
    (,#'u8vector-length   . ,u8vector-length)
    (,#'boolean?          . ,boolean?)
    (,#'bitwise-ior       . ,bitwise-ior)
    (,#'bitwise-xor       . ,bitwise-xor)))

(for ([(name folder) (in-pairs folders)])
  (add-constant-folder name folder))