#lang racket/base
(require pollen/decode
         pollen/tag
         txexpr
         racket/list
         racket/string
         racket/format
         "thumbs.rkt")

(provide piece gallery fig image works work process-note section-intro
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
            ,@(if (non-empty-string? title) (list `(h1 ,title)) empty)
            ,@(if (null? dl-items) empty (list `(dl [[class "piece-meta"]] ,@dl-items)))
            (div [[class "piece-body"]]
                 ,@(decode-elements body
                                    #:txexpr-elements-proc decode-paragraphs
                                    #:string-proc (compose1 smart-quotes smart-dashes)))))

;; ─── gallery ─────────────────────────────────────────────────────────
(define (gallery . items)
  `(div [[class "gallery"]]
        ,@(for/list ([fig (in-list (filter txexpr? items))] [i (in-naturals)])
            ;; the first picture is usually the largest thing on screen:
            ;; load it at once (the rest load as they come into view)
            (if (zero? i) (eager-img fig #t) fig))))

(define (eager-img fig first?)
  (map-elements (lambda (x)
                  (if (and (txexpr? x) (eq? (get-tag x) 'img))
                      (let ([x (remove-attrs-named x 'loading)])
                        (if first? (attr-set x 'fetchpriority "high") x))
                      x))
                fig))

(define (remove-attrs-named x name)
  (txexpr (get-tag x)
          (filter (lambda (a) (not (eq? (car a) name))) (get-attrs x))
          (get-elements x)))

;; a gallery cell is about a quarter of the page wide (half on tablets,
;; all of it on phones)
(define gallery-sizes "(max-width: 600px) 100vw, (max-width: 900px) 50vw, 25vw")

;; ─── fig ─────────────────────────────────────────────────────────────
(define (fig src #:alt [alt ""] . caption)
  `(figure [[class "gallery-item"]]
           ,(page-img src alt #:sizes gallery-sizes)
           ,@(if (andmap whitespace? caption)
                 empty
                 (list `(figcaption ,@caption)))))

;; Pages show resized copies (lib/thumbs.rkt; site-absolute paths only):
;; srcset offers 400–1600px so small screens and gallery cells load
;; small files; src (the 1600px copy) is what the viewer enlarges, and
;; data-full keeps the original for its loupe and 1:1 view.
;; Width and height reserve the space before it loads (no layout jump);
;; eager images (a page's main picture, the first gallery cells) load
;; first instead of lazily.
(define (page-img src alt #:eager [eager #f] #:sizes [sizes "100vw"])
  (define shown (resized src 1600))
  (define-values (w h) (image-size shown))
  ;; one copy per width: small originals give the same copy twice
  (define candidates
    (map cdr
         (remove-duplicates
          (filter values
                  (for/list ([size (in-list '(400 600 800 1200 1600))])
                    (define copy (resized src size))
                    (define-values (cw ch) (image-size copy))
                    (and cw (not (equal? copy src)) (cons cw (format "~a ~aw" copy cw)))))
          #:key car)))
  `(img [[src ,shown] [alt ,alt]
         ,@(if (and w h) `([width ,(~a w)] [height ,(~a h)]) empty)
         ,@(if (> (length candidates) 1) `([srcset ,(string-join candidates ", ")] [sizes ,sizes]) empty)
         ,@(if eager '([fetchpriority "high"]) '([loading "lazy"]))
         [decoding "async"]
         ,@(if (equal? shown src) empty (list `[data-full ,src]))]))

;; ─── image ───────────────────────────────────────────────────────────
(define (image src #:alt [alt ""] #:class [cls ""] . caption)
  `(figure [[class ,(string-append "image " cls)]]
           ,(page-img src alt #:eager (regexp-match? #px"\\bhero\\b" cls)
                      #:sizes "(max-width: 1000px) 100vw, 1000px")
           ,@(if (andmap whitespace? caption)
                 empty
                 (list `(figcaption ,@caption)))))

;; ─── works / work ────────────────────────────────────────────────────
;; Index of a section's pieces: a square thumbnail, title and year, each
;; linking to the piece's own page.
(define (works . items)
  `(ul [[class "works"]]
       ,@(for/list ([w (in-list (filter txexpr? items))] [i (in-naturals)])
           (if (zero? i) (eager-img w #t) w))))

;; square crops: 400/800/1200px, the browser picks by cell width
(define (work href #:image img #:title title #:year [year ""])
  (define squares
    (map cdr
         (remove-duplicates
          (filter values
                  (for/list ([size (in-list '(400 800 1200))])
                    (define copy (resized img size 'fill))
                    (define-values (cw ch) (image-size copy))
                    (and cw (cons cw (format "~a ~aw" copy cw)))))
          #:key car)))
  `(li [[class "work"]]
       (a [[href ,href]]
          (img [[src ,(resized img 800 'fill)]
                ,@(if (pair? squares) `([srcset ,(string-join squares ", ")] [sizes ,gallery-sizes]) empty)
                [width "800"] [height "800"]
                [alt ,title] [loading "lazy"] [decoding "async"]])
          (span [[class "work-title"]] ,title)
          ,@(if (non-empty-string? year) (list `(span [[class "work-year"]] ,year)) empty))))

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
