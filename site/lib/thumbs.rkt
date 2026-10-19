#lang racket/base
(require pollen/setup
         racket/file
         racket/path
         racket/port
         racket/string
         racket/system)

;; Resized copies of site images, made with ImageMagick while a page renders
;; and cached under thumbs/ (regenerated when the original changes).
;; Anything that can't be resized falls back to the original path.

(provide resized)

(define thumb-dir "thumbs")

;; ImageMagick 7 installs `magick`; Ubuntu's ImageMagick 6 package `convert`
(define magick
  (or (find-executable-path "magick") (find-executable-path "convert")))

;; ─── resized ─────────────────────────────────────────────────────────
;; (resized "/images/a.png" 400 'fill) → "/thumbs/400f/images/a.jpg"
;;   'fill — shortest side becomes size (thumbnails cropped to a square)
;;   'fit  — longest side becomes size (images shown whole in viewers)
;; Only site-absolute paths ("/images/…") are resized; images are never
;; enlarged.
(define (resized src size [mode 'fit])
  (cond
    [(not (and magick (string-prefix? src "/"))) src]
    [else
     (define root (current-project-root))
     (define rel (substring src 1))
     (define source (build-path root rel))
     (define out-rel
       (string-append thumb-dir "/" (number->string size) (if (eq? mode 'fill) "f" "") "/"
                      (path->string (path-replace-extension rel #".jpg"))))
     (define out (build-path root out-rel))
     (cond
       [(not (file-exists? source))
        (eprintf "thumbs: no such image ~a\n" src)
        src]
       [(or (fresh? out source) (make-copy source out size mode))
        (string-append "/" out-rel)]
       [else src])]))

(define (fresh? out source)
  (and (file-exists? out)
       (>= (file-or-directory-modify-seconds out)
           (file-or-directory-modify-seconds source))))

;; Writes to a temp file and renames, so a half-written image is never served.
(define (make-copy source out size mode)
  (make-directory* (path-only out))
  (define tmp (path-add-extension out #".tmp"))
  (define geometry
    (format (if (eq? mode 'fill) "~ax~a^>" "~ax~a>") size size))
  (define ok?
    (parameterize ([current-output-port (open-output-nowhere)]
                   [current-error-port (open-output-nowhere)])
      (system* magick
               (string-append (path->string source) "[0]") ; first frame only
               "-auto-orient"                              ; phone photos
               "-resize" geometry
               "-background" "white" "-alpha" "remove" "-alpha" "off"
               "-strip" "-quality" "82" "-interlace" "Plane"
               (string-append "jpg:" (path->string tmp)))))
  (cond
    [ok? (rename-file-or-directory tmp out #t) #t]
    [else
     (when (file-exists? tmp) (delete-file tmp))
     (eprintf "thumbs: could not resize ~a\n" source)
     #f]))
