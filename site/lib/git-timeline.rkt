#lang racket/base
(require racket/system
         racket/string
         racket/list
         racket/port
         racket/path)

(provide git-timeline piece-commits)

;; Find the git repo root by walking up from the pollen project
(define (find-git-root [start (current-directory)])
  (let loop ([dir (simplify-path (path->complete-path start))])
    (cond
      [(directory-exists? (build-path dir ".git")) dir]
      [(equal? dir (simplify-path (build-path dir 'up))) #f]
      [else (loop (simplify-path (build-path dir 'up)))])))

;; Parse git log output into list of (hash date subject)
(define (piece-commits piece-path)
  (define root (find-git-root))
  (unless root (error 'piece-commits "not in a git repository"))
  (define full-path
    (if (complete-path? piece-path)
        piece-path
        (build-path (current-directory) piece-path)))
  (define rel-path
    (find-relative-path root full-path))
  (define cmd
    (format "git -C ~a log --format='%H|||%ai|||%s' --follow -- ~a"
            (path->string root)
            (path->string rel-path)))
  (define output (with-output-to-string (lambda () (system cmd))))
  (define lines (filter non-empty-string? (string-split output "\n")))
  (reverse
   (for/list ([line (in-list lines)])
     (define parts (string-split line "|||"))
     (if (>= (length parts) 3)
         (list (car parts)
               (string-trim (cadr parts))
               (string-trim (string-join (cddr parts) "|||")))
         (list "" "" line)))))

;; Tag function: render timeline as HTML
(define (git-timeline piece-path)
  (define commits (piece-commits piece-path))
  (if (null? commits)
      `(div [[class "timeline"]]
            (p "No process history yet."))
      `(div [[class "timeline"]]
            (h3 "Process journal")
            (ol [[class "timeline-list"]]
                ,@(for/list ([c (in-list commits)])
                    (define date (car (string-split (cadr c) " ")))
                    (define subject (caddr c))
                    `(li [[class "timeline-entry"]]
                         (time ,date)
                         (span [[class "timeline-subject"]] ,subject)))))))

(define (non-empty-string? s)
  (and (string? s) (> (string-length s) 0)))
