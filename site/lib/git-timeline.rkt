#lang racket/base
(require racket/system
         racket/string
         racket/list
         racket/port
         racket/path
         racket/runtime-path)

(provide git-timeline piece-commits)

;; Find the git repo root by walking up from the pollen project
(define (find-git-root [start (current-directory)])
  (let loop ([dir (simplify-path (path->complete-path start))])
    (cond
      ;; .git is a folder in a normal checkout, a file in a worktree
      [(let ([g (build-path dir ".git")]) (or (directory-exists? g) (file-exists? g))) dir]
      [(equal? dir (simplify-path (build-path dir 'up))) #f]
      [else (loop (simplify-path (build-path dir 'up)))])))

;; piece paths ("textiles/sofreh-interlace") are relative to the site
;; folder, wherever Pollen is rendering from
(define-runtime-path site-root "..")

;; Only commits written as journal entries ("weave: …", see the README)
;; appear: other commits that touch the folder are site maintenance.
(define journal-prefixes '("sketch" "swatch" "warp" "weave" "note" "photo" "finish"))

(define (journal-entry? subject)
  (for/or ([p (in-list journal-prefixes)])
    (string-prefix? (string-downcase subject) (string-append p ":"))))

;; Parse git log output into list of (hash date subject)
(define (piece-commits piece-path)
  (define root (find-git-root site-root))
  (unless root (error 'piece-commits "not in a git repository"))
  (define full-path
    (if (complete-path? piece-path)
        piece-path
        (simplify-path (build-path site-root piece-path))))
  (define rel-path
    (find-relative-path root full-path))
  (define git (find-executable-path "git"))
  (define output
    (if git
        (with-output-to-string
          (lambda ()
            (parameterize ([current-error-port (open-output-nowhere)])
              (system* git "-C" (path->string root) "log" "--format=%H|||%ai|||%s"
                       "--follow" "--" (path->string rel-path)))))
        ""))
  (define lines (filter non-empty-string? (string-split output "\n")))
  ;; only well-formed lines: hash, date, subject
  (reverse
   (for*/list ([line (in-list lines)]
               [parts (in-value (string-split line "|||"))]
               #:when (and (>= (length parts) 3)
                           (non-empty-string? (string-trim (cadr parts)))
                           (journal-entry? (string-trim (string-join (cddr parts) "|||")))))
     (list (car parts)
           (string-trim (cadr parts))
           (string-trim (string-join (cddr parts) "|||"))))))

;; Tag function: render timeline as HTML
(define (git-timeline piece-path)
  (define commits (piece-commits piece-path))
  ;; nothing to show yet: show nothing (rather than an empty heading)
  (if (null? commits)
      ""
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
