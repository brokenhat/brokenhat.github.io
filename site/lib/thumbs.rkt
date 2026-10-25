#lang racket/base
(require racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         racket/runtime-path)

;; Resized copies of site images, made with ImageMagick while a page renders
;; and cached under thumbs/ (regenerated when the original changes).
;; Anything that can't be resized falls back to the original path.

(provide resized image-size)

;; The site root, from this file's location: Pollen's current-project-root
;; is the folder being rendered, which for pages outside the pagetree
;; (rendered folder by folder) is their own subfolder.
(define-runtime-path root "..")

(define thumb-dir "thumbs")

;; ImageMagick 7 installs `magick`; Ubuntu's ImageMagick 6 package `convert`
(define magick
  (or (find-executable-path "magick") (find-executable-path "convert")))

;; ImageMagick 7: `magick identify`; 6: a separate `identify`
(define identify
  (cond [(and magick (regexp-match? #rx"magick(\\.exe)?$" (path->string magick)))
         (list magick "identify")]
        [(find-executable-path "identify") => list]
        [else #f]))

;; ─── image-size ──────────────────────────────────────────────────────
;; (image-size "/thumbs/1600/a.jpg") → (values 1600 1067), or #f #f.
;; Read from the file header (fast); remembered per file and mtime.
(define sizes (make-hash))

(define (image-size src)
  (define file (and (string-prefix? src "/") (build-path root (substring src 1))))
  (cond
    [(not (and identify file (file-exists? file))) (values #f #f)]
    [else
     (define key (cons (path->string file) (file-or-directory-modify-seconds file)))
     (define wh
       (hash-ref! sizes key
                  (lambda ()
                    (define out
                      (with-output-to-string
                        (lambda ()
                          (parameterize ([current-error-port (open-output-nowhere)])
                            (apply system* (append identify
                                                   (list "-format" "%w %h"
                                                         (string-append (path->string file) "[0]"))))))))
                    (match-dims out))))
     (if wh (values (car wh) (cdr wh)) (values #f #f))]))

(define (match-dims s)
  (define m (regexp-match #px"^(\\d+) (\\d+)" s))
  (and m (cons (string->number (cadr m)) (string->number (caddr m)))))

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
               ;; 4:2:0 colour + q78: much smaller files, no visible difference
               "-strip" "-sampling-factor" "4:2:0" "-quality" "78" "-interlace" "Plane"
               (string-append "jpg:" (path->string tmp)))))
  (cond
    [ok? (rename-file-or-directory tmp out #t) #t]
    [else
     (when (file-exists? tmp) (delete-file tmp))
     (eprintf "thumbs: could not resize ~a\n" source)
     #f]))
