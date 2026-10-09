#lang racket/base
(require pollen/decode
         pollen/tag
         txexpr
         racket/list
         racket/string
         racket/format)

(provide piece gallery fig image process-note section-intro
         cv-section cv-entry exhibition award
         lede aside smallcaps blockquote link ext-link
         £ title)

;; ─── parse-dimensions ────────────────────────────────────────────────
;; Extract width and height (cm) from a dimensions string.
;; Returns a list of attribute pairs, e.g. (["data-w" "100"] ["data-h" "80"])
(define (parse-dimensions s)
  (define num-rx "([0-9]+(?:[.][0-9]+)?)")
  (cond
    [(not (non-empty-string? s)) '()]
    ;; "h:114 w:141" or "w:141 h:114"
    [(regexp-match (pregexp (string-append "(?i:[hH])\\s*:\\s*" num-rx)) s)
     => (lambda (mh)
          (define h (cadr mh))
          (define mw (regexp-match (pregexp (string-append "(?i:[wW])\\s*:\\s*" num-rx)) s))
          (if mw
              (list (list 'data-w (cadr mw)) (list 'data-h h))
              (list (list 'data-h h))))]
    [(regexp-match (pregexp (string-append "(?i:[wW])\\s*:\\s*" num-rx)) s)
     => (lambda (mw)
          (list (list 'data-w (cadr mw))))]
    ;; "100cm x 110cm" or "100 x 110" — first number x second number
    [(regexp-match (pregexp (string-append num-rx "\\s*(?:cm)?\\s*[xX\u00d7]\\s*" num-rx)) s)
     => (lambda (m)
          (list (list 'data-w (cadr m)) (list 'data-h (caddr m))))]
    ;; "approx 200cm high" — only height
    [(regexp-match (pregexp (string-append num-rx "\\s*(?:cm)?\\s*(?i:high)")) s)
     => (lambda (m)
          (list (list 'data-h (cadr m))))]
    ;; "approx 200cm wide" — only width
    [(regexp-match (pregexp (string-append num-rx "\\s*(?:cm)?\\s*(?i:wide)")) s)
     => (lambda (m)
          (list (list 'data-w (cadr m))))]
    [else '()]))

;; ─── piece ───────────────────────────────────────────────────────────
;; Full piece page: title, metadata dl, and body
(define (piece #:title [title ""]
               #:year [year ""]
               #:technique [technique ""]
               #:fibre [fibre ""]
               #:warp [warp ""]
               #:weft [weft ""]
               #:medium [medium ""]
               #:dimensions [dimensions ""]
               #:exhibition [exh ""]
               #:award [awd ""]
               #:status [status ""]
               . body)
  (define meta-pairs
    (filter pair?
            (list (and (non-empty-string? year)       `("Year" ,year))
                  (and (non-empty-string? technique)  `("Technique" ,technique))
                  (and (non-empty-string? fibre)      `("Fibre" ,fibre))
                  (and (non-empty-string? warp)       `("Warp" ,warp))
                  (and (non-empty-string? weft)       `("Weft" ,weft))
                  (and (non-empty-string? medium)     `("Medium" ,medium))
                  (and (non-empty-string? dimensions) `("Dimensions" ,dimensions))
                  (and (non-empty-string? exh)        `("Exhibition" ,exh))
                  (and (non-empty-string? awd)        `("Award" ,awd))
                  (and (non-empty-string? status)     `("Status" ,status)))))
  (define dl-items
    (append* (for/list ([p (in-list meta-pairs)])
               (list `(dt ,(car p)) `(dd ,(cadr p))))))
  (define dim-attrs (parse-dimensions dimensions))
  `(article [[class "piece"] ,@dim-attrs]
            ,@(if (non-empty-string? title) (list `(h2 ,title)) empty)
            ,@(if (null? dl-items) empty (list `(dl [[class "piece-meta"]] ,@dl-items)))
            (div [[class "piece-body"]]
                 ,@(decode-elements body
                                    #:txexpr-elements-proc decode-paragraphs
                                    #:string-proc (compose1 smart-quotes smart-dashes)))))

;; ─── gallery ─────────────────────────────────────────────────────────
(define (gallery . items)
  `(div [[class "gallery"]]
        ,@(filter txexpr? items)))

;; ─── fig ─────────────────────────────────────────────────────────────
(define (fig src #:alt [alt ""] . caption)
  `(figure [[class "gallery-item"]]
           (img [[src ,src] [alt ,alt] [loading "lazy"]])
           ,@(if (andmap whitespace? caption)
                 empty
                 (list `(figcaption ,@caption)))))

;; ─── image ───────────────────────────────────────────────────────────
(define (image src #:alt [alt ""] #:class [cls ""] . caption)
  `(figure [[class ,(string-append "image " cls)]]
           (img [[src ,src] [alt ,alt] [loading "lazy"]])
           ,@(if (andmap whitespace? caption)
                 empty
                 (list `(figcaption ,@caption)))))

;; ─── process-note ────────────────────────────────────────────────────
(define (process-note #:date [date ""] . body)
  `(div [[class "process-note"]]
        ,@(if (non-empty-string? date)
              (list `(time [[class "process-date"]] ,date))
              empty)
        ,@(decode-elements body
                           #:txexpr-elements-proc decode-paragraphs
                           #:string-proc (compose1 smart-quotes smart-dashes))))

;; ─── section-intro ───────────────────────────────────────────────────
(define (section-intro . body)
  `(div [[class "section-intro"]]
        ,@(decode-elements body
                           #:txexpr-elements-proc decode-paragraphs
                           #:string-proc (compose1 smart-quotes smart-dashes))))

;; ─── cv-section ──────────────────────────────────────────────────────
(define (cv-section heading . body)
  `(section [[class "cv-section"]]
            (h2 ,heading)
            ,@body))

;; ─── cv-entry ────────────────────────────────────────────────────────
(define (cv-entry #:year [year ""] . body)
  `(div [[class "cv-entry"]]
        (span [[class "cv-year"]] ,year)
        (span [[class "cv-desc"]] ,@body)))

;; ─── exhibition ──────────────────────────────────────────────────────
(define (exhibition name #:year [year ""] #:venue [venue ""])
  `(div [[class "cv-entry"]]
        (span [[class "cv-year"]] ,year)
        (span [[class "cv-desc"]] ,name
              ,@(if (non-empty-string? venue) (list ", " `(em ,venue)) empty))))

;; ─── award ───────────────────────────────────────────────────────────
(define (award name #:year [year ""])
  `(div [[class "cv-entry"]]
        (span [[class "cv-year"]] ,year)
        (span [[class "cv-desc"]] ,name)))

;; ─── typography helpers ──────────────────────────────────────────────
(define (lede . body)
  `(p [[class "lede"]] ,@body))

(define (aside . body)
  `(aside ,@(decode-elements body
                             #:txexpr-elements-proc decode-paragraphs
                             #:string-proc (compose1 smart-quotes smart-dashes))))

(define (smallcaps . body)
  `(span [[class "smallcaps"]] ,@body))

(define (blockquote . body)
  `(blockquote ,@(decode-elements body
                                  #:txexpr-elements-proc decode-paragraphs
                                  #:string-proc (compose1 smart-quotes smart-dashes))))

(define (link url . body)
  `(a [[href ,url]] ,@body))

(define (ext-link url . body)
  `(a [[href ,url] [target "_blank"] [rel "noopener"]] ,@body))

;; ─── literal £ ───────────────────────────────────────────────────────
(define (£ . _) "£")

;; ─── title helper (used in templates) ────────────────────────────────
(define (title . body)
  `(h1 [[class "page-title"]] ,@body))

;; ─── utility ─────────────────────────────────────────────────────────
(define (whitespace? v)
  (and (string? v) (regexp-match? #rx"^\\s*$" v)))

(define (non-empty-string? s)
  (and (string? s) (not (regexp-match? #rx"^\\s*$" s))))
