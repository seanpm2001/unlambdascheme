(module translate
	(main main))

;;;; elminiate-letrec -> eliminate-let -> curry -> explicify-apply -> eliminate-lambda -> unlambdify

(define (atom? x)
    (not (list? x)))

(define (filter f l)
    (cond ((null? l)
	   '())
	  ((f (car l))
	   (cons (car l) (filter f (cdr l))))
	  (else
	   (filter f (cdr l)))))

(define (list-head l n)
    (if (= n 0)
	'()
	(cons (car l) (list-head (cdr l) (- n 1)))))

(define (eliminate-high-level x)
    (cond ((eq? x #t)
	   '(lambda (t f)
	     t))
	  ((eq? x #f)
	   '(lambda (t f)
	     f))
	  ((eq? x '())
	   '(lambda (f)
	     (f **i** **i** (lambda (t f) t))))
	  ((eq? x 'cons)
	   '(lambda (a b) (lambda (consf) (consf a b (lambda (t f) f)))))
	  ((eq? x 'car)
	   '(lambda (c) (c (lambda (cara b p) cara))))
	  ((eq? x 'cdr)
	   '(lambda (c) (c (lambda (cdra b p) b))))
	  ((eq? x 'null?)
	   '(lambda (c) (c (lambda (nulla b p) p))))
	  ((eq? x 'poor-cons)
	   '(lambda (a) (lambda (b) (lambda (poorconsf) ((poorconsf a) b)))))
	  ((eq? x 'poor-car)
	   '(lambda (c) (c (lambda (poorcara) (lambda (b) poorcara)))))
	  ((eq? x 'poor-cdr)
	   '(lambda (c) (c (lambda (poorcdra) (lambda (b) b)))))
	  ((atom? x)
	   x)
	  ((eq? (car x) 'lambda)
	   `(lambda ,(cadr x) ,(eliminate-high-level (caddr x))))
	  ((eq? (car x) 'poor-if)
	   (eliminate-high-level `(,(cadr x) ,(caddr x) ,(cadddr x))))
	  ((eq? (car x) 'if)
	   `(((lambda (c t e) (c t e))
	      ,(eliminate-high-level (cadr x))
	      (lambda () ,(eliminate-high-level (caddr x)))
	      (lambda () ,(eliminate-high-level (cadddr x))))))
	  ((eq? (car x) 'cond)
	   (cond ((null? (cdr x))
		  (eliminate-high-level #f))
		 ((eq? (caadr x) 'else)
		  (eliminate-high-level (cadadr x)))
		 (else
		  (eliminate-high-level `(if ,(caadr x)
					  ,(cadadr x)
					  ,(eliminate-high-level `(cond ,@(cddr x))))))))
	  ((eq? (car x) 'not)
	   `(lambda (t f)
	     (,(eliminate-high-level (cadr x)) f t)))
	  ((eq? (car x) 'poor-and)
	   (eliminate-high-level `(,(cadr x) ,(caddr x) #f)))
	  ((eq? (car x) 'and)
	   (eliminate-high-level `(if ,(cadr x) ,(caddr x) #f)))
	  ((eq? (car x) 'poor-or)
	   `(,(cadr x) #t ,(caddr x)))
	  ((eq? (car x) 'or)
	   (eliminate-high-level `(if ,(cadr x) #t ,(caddr x))))
	  ((eq? (car x) 'begin)
	   (if (null? (cddr x))
	       (eliminate-high-level (cadr x))
	       `((lambda (*dummy*) ,(eliminate-high-level `(begin ,@(cddr x)))) ,(eliminate-high-level (cadr x)))))
	  ((eq? (car x) 'write-char)
	   `((*write-char* ,(cadr x)) **i**))
	  ((eq? (car x) 'is-char?)
	   `((*is-char* ,(cadr x)) **i**))
	  ((eq? (car x) 'read-char?)
	   `(**read-char** **i**))
	  ((eq? (car x) 'read-char=?)
	   `((**read-char=** ,(cadr x)) **i**))
	  (else
	   (map eliminate-high-level x))))

(define (eliminate-letrec x)
    (letrec ((eliminate (lambda (x fs)
			  (cond ((or (atom? x) (null? x))
				 (let ((a (assq x fs)))
				   (if a
				       (cdr a)
				       x)))
				((eq? (car x) 'lambda)
				 (let ((a (cadr x))
				       (b (caddr x)))
				   `(lambda ,a ,(eliminate b (filter (lambda (x) (not (memq (car x) a))) fs)))))
				((eq? (car x) 'letrec)
				 (let* ((fns (map car (cadr x)))
					(new-fs (append (map (lambda (x)
							       (let ((l (cadr x)))
								 (cons (car x)
								       `(lambda ,(cadr l) (,(car x) ,@(cadr l) ,@fns)))))
							     (cadr x))
							fs)))
				   `((lambda ,fns
				       ,(eliminate (caddr x) new-fs))
				     ,@(map (lambda (x)
					      (let ((l (cadr x)))
						`(lambda (,@(cadr l) ,@fns)
						  ,(eliminate (caddr l) new-fs))))
					    (cadr x)))))
				(else
				 (map (lambda (x) (eliminate x fs)) x))))))
	    (eliminate x '())))

(define (eliminate-let x)
    (cond ((or (atom? x) (null? x))
	   x)
	  ((eq? (car x) 'lambda)
	   `(lambda ,(cadr x) ,(eliminate-let (caddr x))))
	  ((eq? (car x) 'let)
	   (if (symbol? (cadr x))
	       `(letrec ((,(cadr x) (lambda ,(map car (caddr x))
				      ,(eliminate-let (cadddr x)))))
		 (,(cadr x) ,@(map (lambda (x) (eliminate-let (cadr x))) (caddr x))))
	       `((lambda ,(map car (cadr x)) ,(eliminate-let (caddr x))) ,@(map (lambda (x) (eliminate-let (cadr x))) (cadr x)))))
	  (else
	   (map eliminate-let x))))

(define (curry x)
    (cond ((atom? x)
	   x)
	  ((eq? (car x) 'lambda)
	   (let ((a (cadr x))
		 (b (caddr x)))
	     (cond ((null? a)
		    `(lambda (**dummy**) ,(curry b)))
		   ((null? (cdr a))
		    `(lambda ,a ,(curry b)))
		   (else
		    `(lambda (,(car a)) ,(curry `(lambda ,(cdr a) ,b)))))))
	  (else
	   (let ((f (curry (car x)))
		 (a (map curry (cdr x))))
	     (cond ((null? a)
		    `(,f **i**))
		   ((null? (cdr a))
		    `(,f ,@a))
		   (else
		    (curry `((,f ,(car a)) ,@(cdr a)))))))))

(define (pair-curry x)
    (letrec ((make-subs (lambda (args path)
			  (cond ((null? args)
				 '())
				((= (length args) 1)
				 (list (cons (car args) path)))
				(else
				 (let* ((half (quotient (length args) 2))
					(car-args (list-head args half))
					(cdr-args (list-tail args half)))
				   (append (make-subs car-args (list 'poor-car path))
					   (make-subs cdr-args (list 'poor-cdr path))))))))
	     (make-args (lambda (args)
			  (cond ((null? args)
				 '**i**)
				((= (length args) 1)
				 (car args))
				(else
				 (let* ((half (quotient (length args) 2))
					(car-args (list-head args half))
					(cdr-args (list-tail args half)))
				   `((poor-cons ,(make-args car-args)) ,(make-args cdr-args)))))))
	     (curry (lambda (x subs)
		      (cond ((atom? x)
			     (let ((sub (assq x subs)))
			       (if sub
				   (cdr sub)
				   x)))
			    ((eq? (car x) 'lambda)
			     (let ((a (cadr x))
				   (b (caddr x)))
			       (if (null? a)
				   `(lambda (**dummy**) ,(curry b subs))
				   (let ((argname (gensym)))
				     `(lambda (,argname) ,(curry b (append (make-subs a argname) subs)))))))
			    (else
			     (let ((f (curry (car x) subs))
				   (a (map (lambda (x) (curry x subs)) (cdr x))))
			       `(,f ,(make-args a))))))))
	    (curry x '())))

(define (pass-through? x)
    (or (and (list? x)
	     (or (eq? (car x) '*write-char*)
		 (eq? (car x) '**read-char=**)
		 (eq? (car x) '*is-char*)))
	(or (eq? x '**i**) (eq? x '**k**) (eq? x '**read-char**))))

(define (pass-through-predicate? x)
    (or (and (list? x) (eq? (car x) '**read-char=**))
	(eq? x '**read-char**)))

(define *current-char* '())
(define *input-string* "kurdenb")

;(define (**i** x) x)
;(define (**k** x) (lambda (y) x))
;(define (**s** x) (lambda (y) (lambda (z) ((x z) (y z)))))
;(define (*write-char* x) (lambda (y) (write-char x) y))

(define (natify x bindings)
    (cond ((eq? x '**i**)
	   (lambda (x) x))
	  ((eq? x '**k**)
	   (lambda (x) (lambda (y) x)))
	  ((eq? x '**read-char**)
	   (lambda (y)
	     (if (= (string-length *input-string*) 0)
		 '(() . (lambda (lambda (get 0))))
		 (begin
		  (set! *current-char* (string-ref *input-string* 0))
		  (set! *input-string* (substring *input-string* 1 (string-length *input-string*)))
		  '(() . (lambda (lambda (get 1))))))))
	  ((eq? (car x) '**read-char=**)
	   (lambda (y)
	     (if (char=? *current-char* (cadr x))
		 '(() . (lambda (lambda (get 1))))
		 '(() . (lambda (lambda (get 0)))))))
	  ((eq? (car x) '*write-char*)
	   (lambda (y) (write-char (cadr x)) y))
	  ((eq? (car x) 'lambda)
	   (lambda (value)
	     ((natify (caddr x) (cons (cons (caadr x) value) bindings))
	      '(lambda (get 0)))))
	  (else
	   (error "natify" "unknown native" x))))

(define (optimize-curried x)
    (cond ((or (atom? x) (pass-through? x))
	   x)
	  ((eq? (car x) 'lambda)	;(lambda (a) (lambda (b) a)) -> **k**
	   (let ((a (caadr x))
		 (b (caddr x)))
	     (if (and (list? b)
		      (eq? (car b) 'lambda)
		      (not (eq? (caadr b) a))
		      (eq? (caddr b) a))
		 '**k**
		 `(lambda (,a) ,(optimize-curried b)))))
	  (else
	   (list (optimize-curried (car x)) (optimize-curried (cadr x))))))

(define (compile-to-bytecode x)
    (letrec ((index (lambda (x e)
		      (cond ((null? e)
			     (display "not bound: ")
			     (display x)
			     (newline)
			     0)
			    ((eq? x (car e))
			     0)
			    (else
			     (+ 1 (index x (cdr e)))))))
	     (compile (lambda (x e)
			(cond ((eq? x '**i**)
			       (compile '(lambda (x) x) '()))
			      ((pass-through-predicate? x)
			       (list 'native `(lambda (**dummy**)
					       (if (,x **i**)
						   ,(bytecode->scheme (scheme->bytecode #t))
						   ,(bytecode->scheme (scheme->bytecode #f))))))
			      ((pass-through? x)
			       (list 'native x))
			      ((atom? x)
			       (let ((i (index x e)))
				 (list 'get i)))
			      ((eq? (car x) 'lambda)
			       (list 'lambda (compile (caddr x) (cons (caadr x) e))))
			      (else
			       (list 'apply (compile (car x) e) (compile (cadr x) e)))))))
	    (compile x '())))

(define (interpret-bytecode x)
    (letrec ((get (lambda (e p)
		    (if (= p 0)
			e
			(get (cdr e) (- p 1)))))
	     (interpret (lambda (x e)
			  (let ((type (car x)))
			    (cond ((eq? type 'lambda)
				   (cons e (cadr x)))
				  ((eq? type 'apply)
				   (let ((f (interpret (cadr x) e))
 					 (a (interpret (caddr x) e)))
				     (interpret (cdr f) (cons a (car f)))))
				  ((eq? type 'get)
				   (car (get e (cadr x))))
				  ((eq? type 'native)
				   ((natify (cadr x) '()) '(lambda (get 0)))))))))
	    (interpret x '())))

(define (bytecode->scheme x)
    (letrec ((number->scheme (lambda (n)
			       (if (= 0 n)
				   '()
				   `(cons ,(if (= (remainder n 2) 1)
					       'poor-cdr
					       '**i**)
				     ,(number->scheme (quotient n 2))))))
	     (transform (lambda (x)
			  (let ((type (car x)))
			    (cond ((eq? type 'lambda)
				   `((poor-cons ((poor-cons #t) #t)) ,(transform (cadr x))))
				  ((eq? type 'apply)
				   `((poor-cons ((poor-cons #t) #f)) ((poor-cons ,(transform (cadr x))) ,(transform (caddr x)))))
				  ((eq? type 'get)
				   `((poor-cons ((poor-cons #f) #t)) ,(number->scheme (cadr x))))
				  ((eq? type 'native)
				   `((poor-cons ((poor-cons #f) #f)) ,(cadr x))))))))
	    (transform x)))

(define (unbound-in? a x)
    (cond ((atom? x)
	   (eq? x a))
	  ((pass-through? x)
	   #f)
	  ((eq? (car x) 'lambda)
	   (if (eq? (caadr x) a)
	       #f
	       (unbound-in? a (caddr x))))
	  (else
	   (or (unbound-in? a (car x)) (unbound-in? a (cadr x))))))

(define (contains-variables? x)
    (cond ((pass-through? x)
	   #f)
	  ((atom? x)
	   #t)
	  (else
	   (or (contains-variables? (car x))
	       (contains-variables? (cadr x))))))

(define (lambda-depth x)
    (cond ((or (atom? x) (pass-through? x))
	   0)
	  ((eq? (car x) 'lambda)
	   (let ((depth (lambda-depth (caddr x))))
	     (if (unbound-in? (caadr x) (caddr x))
		 (+ 1 depth)
		 depth)))
	  (else
	   (max (lambda-depth (car x)) (lambda-depth (cadr x))))))

;(define (explicify-apply x)
;    (cond ((or (atom? x) (pass-through? x))
;	   x)
;	  ((eq? (car x) 'lambda)
;	   `(lambda ,(cadr x) ,(explicify-apply (caddr x))))
;	  (else
;	   `(**apply** ,(explicify-apply (car x)) ,(explicify-apply (cadr x))))))

(define (eliminate-lambda x)
    (letrec ((eliminate (lambda (x)
			  (cond ((or (atom? x) (pass-through? x))
				 x)
				((eq? (car x) '**d**)
				 x)
				((eq? (car x) 'lambda)
				 (let ((a (caadr x))
				       (b (caddr x)))
				   (cond ((eq? a b)
					  '**i**)
					 ((or (atom? b)
					      (pass-through? b))
					  (if (eq? b '**d**)
					      (display "kurd"))
					  `(**k** ,b))
					 ((and (not (unbound-in? a b))
					       (not (contains-variables? b)))
					  `(**d** (**k** ,(eliminate b))))
					 ((eq? (car b) 'lambda)
					  (eliminate `(lambda (,a) ,(eliminate b))))
					 (else
					  (let ((g (car b))
						(h (cadr b)))
					    (if (eq? g '**d**)
						(begin
						 (if (contains-variables? h)
						     (display "heusl"))
						 `(**k** ,b))
						`((**s** ,(eliminate `(lambda (,a) ,g))) ,(eliminate `(lambda (,a) ,h)))))))))
				(else
				 `(,(eliminate (car x)) ,(eliminate (cadr x))))))))
	    (eliminate x)))

(define (eliminate-d x)
    (cond ((or (atom? x) (pass-through? x))
	   x)
	  ((eq? (car x) '**d**)
	   `(lambda (x) (,(eliminate-d (cadr x)) x)))
	  (else
	   `(,(eliminate-d (car x)) ,(eliminate-d (cadr x))))))

(define (unlambdify x)
    (cond ((eq? x '**i**)
	   (write-char #\i))
	  ((eq? x '**k**)
	   (write-char #\k))
	  ((eq? x '**s**)
	   (write-char #\s))
	  ((eq? x '**d**)
	   (write-char #\d))
	  ((eq? x '**read-char**)
	   (display "`d`k``")
	   (display "`@``s`kc``s`k`s`k`k`ki``ss`k`kk") ;(lambda (t) (lambda (f) (if (read-char?) t f)))
	   (scheme->unlambda #t)
	   (scheme->unlambda #f))
	  ((eq? (car x) '**read-char=**)
	   (display "`d`k``")
	   (display "`?")
	   (write-char (cadr x))
	   (display "``s`kc``s`k`s`k`k`ki``ss`k`kk") ;(lambda (t) (lambda (f) (if (read-char=? c) t f)))
	   (scheme->unlambda #t)
	   (scheme->unlambda #f))
	  ((eq? (car x) '*write-char*)
	   (write-char #\.)
	   (write-char (cadr x)))
	  (else				;(eq? (car x) '**apply**)
	   (write-char #\`)
	   (unlambdify (car x))
	   (unlambdify (cadr x)))))

(define (scheme->unlambda x)
    (unlambdify (eliminate-lambda (optimize-curried (curry (eliminate-high-level (pair-curry (eliminate-high-level (eliminate-letrec (eliminate-let x))))))))))

(define (scheme->bytecode x)
    (compile-to-bytecode (curry (eliminate-high-level (eliminate-letrec (eliminate-let x))))))

(define (letrecify-from-port port)
    (letrec ((r (lambda (fs)
		  (let ((x (read port)))
		    (if (eq? (car x) 'define)
			(r (cons (cons (cadr x) (caddr x)) fs))
			`(letrec ,(map (lambda (x)
					 (let ((f (caar x))
					       (a (cdar x))
					       (b (cdr x)))
					   `(,f (lambda ,a ,b))))
				       fs)
			  ,x))))))
	    (r '())))

(define (compile-program infile outfile)
    (with-input-from-file infile
      (with-output-to-file outfile
	(lambda ()
	  (lambda ()
	    (scheme->unlambda (letrecify-from-port (current-input-port))))))))

(define (compile-file file)
    (with-input-from-file file
      (lambda ()
	(scheme->unlambda (read)))))

(define (bytecompile-file file)
    (with-input-from-file file
      (lambda ()
	(scheme->unlambda (bytecode->scheme (scheme->bytecode (read)))))))

(define (byteinterpret-file file)
    (let ((bytecode (with-input-from-file file
		      (lambda ()
			(scheme->bytecode (read))))))
      (interpret-bytecode bytecode)))

(define (bytedump-file file)
    (let ((bytecode (with-input-from-file file
		      (lambda ()
			(scheme->bytecode (read))))))
      (write bytecode)
      (newline)))

(define (main argv)
    (args-parse (cdr argv)
		(("-c" ?file (help "directly compile to unlambda"))
		 (compile-file file))
		(("-b" ?file (help "bytecompile to unlambda"))
		 (bytecompile-file file))
		(("-i" ?file (help "bytecompile and interpret bytecode"))
		 (byteinterpret-file file))
		(("-d" ?file (help "bytecompile and dump bytecode"))
		 (bytedump-file file))
		(else
		 (args-parse-usage #f))))