#lang racket/base
(require pollen/setup
         pollen/decode
         pollen/tag
         txexpr
         racket/list
         racket/string
         "lib/tags.rkt"
         "lib/tiles.rkt"
         "lib/git-timeline.rkt")

;; ─── setup ───────────────────────────────────────────────────────────
(module setup racket/base
  (provide (all-defined-out))
  (define poly-targets '(html))
  (define command-char #\£)
  (define server-port 8080)
  (define block-tags (append '(piece gallery figure div section ol ul dl)
                             '(cv-section process-note section-intro)
                             '(h1 h2 h3 h4 article nav aside blockquote header footer))))

;; ─── re-provide tags + tiles + git-timeline for .pm files ────────────
(provide (all-from-out "lib/tags.rkt")
         (all-from-out "lib/tiles.rkt")
         (all-from-out "lib/git-timeline.rkt"))

;; ─── root decoder ────────────────────────────────────────────────────
(provide root)
(define (root . elements)
  (txexpr 'root empty
          (decode-elements elements
                          #:txexpr-elements-proc decode-paragraphs
                          ;; tags that build their own markup (tile-grid) opt out
                          #:exclude-attrs '((data-decoded "true"))
                          #:string-proc (compose1 smart-quotes smart-dashes))))

;; ─── navigation helpers ──────────────────────────────────────────────
(provide site-nav-items copyright-year subpages)
(require pollen/pagetree pollen/template pollen/core racket/date racket/runtime-path)

(define (copyright-year)
  (number->string (date-year (current-date))))

;; Safe meta lookup — returns #f if source file not accessible.
;; The path is made absolute: a relative one resolves against the page
;; being rendered, so from subfolders every lookup failed and nav labels
;; fell back to file names.
(define-runtime-path site-root ".")
(define (safe-title href)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (select-from-metas 'title (build-path site-root href))))

;; Label from path slug
(define (label-from-path href)
  (let* ([slug (car (string-split href "/"))]
         [name (regexp-replace* #rx"\\.(html|pm)$" slug "")]
         [spaced (regexp-replace* #rx"-" name " ")])
    (string-titlecase spaced)))

;; Section pages: top-level pages excluding index.html itself
(define (section-page? sym)
  (let ([s (symbol->string sym)])
    (and (not (equal? s "index.html"))
         (or (not (string-contains? s "/"))
             (regexp-match? #rx"^[^/]+/index\\.html$" s)))))

;; Find direct child pages of a given section page
(define (children-of section-sym)
  (define sec-str (symbol->string section-sym))
  (define dir-prefix
    (let ([parts (string-split sec-str "/")])
      (if (> (length parts) 1)
          (string-append (string-join (reverse (cdr (reverse parts))) "/") "/")
          "")))
  (if (equal? dir-prefix "") empty
      (let ([all-pages (pagetree->list (current-pagetree))])
        (filter (lambda (p)
                  (let ([s (symbol->string p)])
                    (and (not (equal? p section-sym))
                         (string-prefix? s dir-prefix)
                         (let ([rest (substring s (string-length dir-prefix))])
                           (or (not (string-contains? rest "/"))
                               (regexp-match? #rx"^[^/]+/index\\.html$" rest))))))
                all-pages))))

;; Label from deepest meaningful slug
(define (label-from-deep-path href)
  (let* ([parts (string-split href "/")]
         [slug (car (reverse (filter (lambda (s) (not (equal? s "index.html"))) parts)))]
         [name (regexp-replace* #rx"\\.(html|pm)$" slug "")]
         [spaced (regexp-replace* #rx"-" name " ")])
    (string-titlecase spaced)))

;; here: the page being rendered — its link gets aria-current="page" and
;; its section's <li> the class "is-active"
(define (site-nav-items [here #f])
  (define here-sym (cond [(symbol? here) here]
                         [(string? here) (string->symbol here)]
                         [else #f]))
  (define (nav-link p label)
    `(a [[href ,(string-append "/" (symbol->string p))]
         ,@(if (eq? p here-sym) '([aria-current "page"]) empty)]
        ,label))
  (define all-pages (children 'pagetree-root (current-pagetree)))
  (define section-pages (if all-pages (filter section-page? all-pages) empty))
  (for/list ([p (in-list section-pages)])
    (let* ([href (symbol->string p)]
           [label (or (safe-title href) (label-from-path href))]
           [kids (children-of p)]
           [active? (or (eq? p here-sym) (and (memq here-sym kids) #t))]
           [classes (string-join (append (if (null? kids) empty '("has-dropdown"))
                                         (if active? '("is-active") empty))
                                 " ")])
      (define submenu-id
        (string-append "submenu-"
                       (regexp-replace* #rx"[^a-z0-9]+"
                                        (string-downcase (regexp-replace #rx"(/index)?[.]html$" href ""))
                                        "-")))
      `(li ,@(if (equal? classes "") empty `([[class ,classes]]))
           ,(nav-link p label)
           ;; opens the section's subpages in the collapsed (phone) menu;
           ;; hidden on wide screens, where the dropdown opens on hover
           ,@(if (null? kids)
                 empty
                 (list `(button [[class "submenu-toggle"] [type "button"]
                                 [aria-expanded ,(if active? "true" "false")]
                                 [aria-controls ,submenu-id]
                                 [aria-label ,(string-append label " pages")]])))
           ,@(if (null? kids)
                 empty
                 (list `(ul [[class "dropdown"] [id ,submenu-id]]
                            ,@(for/list ([k (in-list kids)])
                                (let* ([khref (symbol->string k)]
                                       [klabel (or (safe-title khref)
                                                   (label-from-deep-path khref))])
                                  `(li ,(nav-link k klabel)))))))))))

;; ─── subpages: list child pages of current section ───────────────────
(define (subpages here-path)
  (define resolved (cond [(procedure? here-path) (here-path)]
                         [(symbol? here-path) here-path]
                         [else (string->symbol here-path)]))
  (define here-str (symbol->string resolved))
  ;; derive the directory prefix from here-path
  ;; e.g. "textiles/index.html" → "textiles/"
  ;;      "highland-series/index.html" → "highland-series/"
  (define dir-prefix
    (let ([parts (string-split here-str "/")])
      (if (> (length parts) 1)
          (string-append (string-join (reverse (cdr (reverse parts))) "/") "/")
          "")))
  (define all-pages (pagetree->list (current-pagetree)))
  (define here-sym (if (symbol? here-path) here-path (string->symbol here-path)))
  ;; find pages that are in our directory (or subdirectories) but not us
  (define child-pages
    (filter (lambda (p)
              (let ([s (symbol->string p)])
                (and (not (equal? p here-sym))
                     (string-prefix? s dir-prefix)
                     ;; direct children only: either section/foo.html
                     ;; or section/sub/index.html (one level deeper)
                     (let ([rest (substring s (string-length dir-prefix))])
                       (or (not (string-contains? rest "/"))
                           (regexp-match? #rx"^[^/]+/index\\.html$" rest))))))
            all-pages))
  (if (null? child-pages)
      ""
      `(nav [[class "subpages"]]
            (ul ,@(for/list ([p (in-list child-pages)])
                    (let* ([href (symbol->string p)]
                           [label (or (safe-title href)
                                      ;; derive label from deepest slug
                                      (let* ([parts (string-split href "/")]
                                             [slug (car (reverse (filter
                                                                  (lambda (s) (not (equal? s "index.html")))
                                                                  parts)))]
                                             [name (regexp-replace* #rx"\\.(html|pm)$" slug "")]
                                             [spaced (regexp-replace* #rx"-" name " ")])
                                        (string-titlecase spaced)))])
                      `(li (a [[href ,(string-append "/" href)]] ,label))))))))
