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
         youtube
         £ title)

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
    (for/list ([p (in-list meta-pairs)])
      `(div [[class "meta-pair"]] (dt ,(car p)) (dd ,(cadr p)))))
  `(article [[class "piece"]]
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

;; ─── youtube ─────────────────────────────────────────────────────
(define (youtube id . body)
  `(div [[class "youtube-embed"]]
        (iframe [[src ,(format "https://www.youtube.com/embed/~a" id)]
                 [title "YouTube video"]
                 [frameborder "0"]
                 [allow "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"]
                 [allowfullscreen "true"]])))

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
