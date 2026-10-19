#lang racket/base
(require pollen/decode
         txexpr
         racket/list
         racket/string
         racket/format
         "thumbs.rkt")

;; Tile-grid subpage tags — a static port of blog-tile's pan/zoom grid.
;; Tiles are rendered to HTML here; js/tile-grid.js only positions them
;; and handles pan, zoom, and the tile viewers.

(provide tile-grid tile sketch-page)

;; ─── tile-grid ───────────────────────────────────────────────────────
;; Container for tiles. Empty neighbour cells are added client-side.
(define (tile-grid . items)
  `(div [[class "tile-grid"] [data-decoded "true"]]
        (div [[class "tile-grid__viewport"] [tabindex "0"]
              [aria-label "Tile grid. Drag to pan, scroll to zoom."]]
             (div [[class "tile-grid__plane"]]
                  ,@(filter txexpr? items)))
        (div [[class "tile-grid__controls"]]
             (button [[type "button"] [data-tile-action "zoom-in"] [aria-label "Zoom in"]] "+")
             (button [[type "button"] [data-tile-action "zoom-out"] [aria-label "Zoom out"]] "−")
             (button [[type "button"] [data-tile-action "fit"] [aria-label "Fit all tiles"]] "⤢"))))

;; ─── tile ────────────────────────────────────────────────────────────
;; One cell at grid coordinate (x, y); y grows upward, as in blog-tile.
;; Type is inferred: sketch-page children → sketchbook, #:image → image,
;; otherwise text. Pass #:type to force it.
(define (tile #:x x
              #:y y
              #:type [type #f]
              #:title [title ""]
              #:image [img ""]
              #:caption [caption ""]
              #:date [date ""]
              #:focus [focus "50% 50%"]
              #:zoom [zoom 1]
              #:bg [bg ""]
              . body)
  (define pages (filter (lambda (e) (and (txexpr? e) (attr-ref e 'data-sketch-src #f))) body))
  (define rest-body (filter (lambda (e) (not (memq e pages))) body))
  (define kind
    (cond [type type]
          [(pair? pages) "sketchbook"]
          [(non-empty-string? img) "image"]
          [else "text"]))
  ;; the original image; tiles and viewers get resized copies of it
  (define cover (if (non-empty-string? img)
                    img
                    (if (pair? pages) (attr-ref (car pages) 'data-full) "")))
  (define label (if (non-empty-string? title) title (format "tile ~a, ~a" x y)))
  (define style (if (non-empty-string? bg) (format "background: ~a" bg) ""))

  (define topbar
    (if (non-empty-string? date)
        (list `(div [[class "grid-cell__topbar"]]
                    (span [[class "grid-cell__date"]] ,date)))
        empty))

  (define thumb
    (if (non-empty-string? cover)
        (list `(img [[class "grid-cell__image"]
                     [src ,(resized cover 400 'fill)]
                     [srcset ,(format "~a 1x, ~a 2x" (resized cover 400 'fill) (resized cover 800 'fill))]
                     [data-large ,(resized cover 1600)]
                     [data-full ,cover]
                     [alt ,label]
                     [loading "lazy"] [decoding "async"] [draggable "false"]
                     [style ,(format "object-position: ~a; transform-origin: ~a; transform: scale(~a)"
                                     focus focus zoom)]]))
        empty))

  (define overlay
    `(div [[class "grid-cell__overlay"]]
          (span [[class "grid-cell__coord"]] ,(format "~a, ~a" x y))
          (strong ,title)
          (em ,(cond [(equal? kind "sketchbook")
                      (format "~a page~a" (length pages) (if (= (length pages) 1) "" "s"))]
                     [(non-empty-string? caption) caption]
                     [else ""]))))

  (define content
    (case kind
      [("image")
       (append thumb
               (list overlay)
               ;; optional text: opens the image + text dialog instead of the lightbox
               (if (andmap whitespace? rest-body)
                   empty
                   (list `(div [[class "grid-cell__description"] [hidden ""]]
                               ,@(decode-body rest-body)))))]
      [("sketchbook")
       (append thumb
               (list `(span [[class "grid-cell__sketchbook-badge"]] ,(format "~a pg" (length pages)))
                     overlay
                     `(div [[class "grid-cell__pages"] [hidden ""]] ,@pages)))]
      [else
       (list `(div [[class "grid-cell__text-wrap"]]
                   (h4 [[class "grid-cell__text-title"]] ,title)
                   (div [[class "grid-cell__text-body"]] ,@(decode-body rest-body))
                   (span [[class "grid-cell__text-more"] [aria-hidden "true"]] "...")))]))

  `(div [[class ,(format "grid-cell grid-cell--~a" kind)]
         [role "button"] [tabindex "-1"]
         [data-x ,(~a x)] [data-y ,(~a y)] [data-type ,kind]
         [data-title ,title]
         [aria-label ,label]
         ,@(if (non-empty-string? style) (list `[style ,style]) empty)]
        ,@topbar
        ,@content))

;; ─── sketch-page ─────────────────────────────────────────────────────
;; One page of a sketchbook tile. Not loaded until the book is opened.
(define (sketch-page src #:alt [alt ""])
  `(span [[data-sketch-src ,(resized src 1600)] [data-full ,src] [data-alt ,alt]]))

;; ─── utility ─────────────────────────────────────────────────────────
(define (decode-body elements)
  (decode-elements elements
                   #:txexpr-elements-proc decode-paragraphs
                   #:string-proc (compose1 smart-quotes smart-dashes)))

(define (whitespace? v)
  (and (string? v) (regexp-match? #rx"^\\s*$" v)))

(define (non-empty-string? s)
  (and (string? s) (not (regexp-match? #rx"^\\s*$" s))))
