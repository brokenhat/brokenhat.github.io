#lang racket/base
(require racket/string
         racket/list
         racket/format
         racket/port
         racket/system
         racket/runtime-path
         json
         txexpr
         pollen/core
         pollen/pagetree
         pollen/template
         "thumbs.rkt")

;; Search engines and link previews: the <head> tags of every page
;; (title, description, canonical, Open Graph, JSON-LD), clean URLs,
;; and the sitemap. Page metas it reads:
;;   title        page name ("Textiles")
;;   seo-title    full <title> instead of "title — Dominik Zarzycki"
;;   description  ~150 characters for results and previews (else taken
;;                from the page's first paragraphs)
;;   image        preview image (else the page's first image)
;;   noindex      "yes": kept out of search results and the sitemap
;;   event-*      on an exhibition page: start, end (YYYY-MM-DD), venue,
;;                street, locality, postcode, country

(provide seo-head clean-href sitemap-xml site-url)

(define-runtime-path root "..")
(define-runtime-path ptree-file "../index.ptree")

(define site-url "https://brokenhat.github.io")
(define site-name "Dominik Zarzycki")
(define default-image "/textiles/bivium-tends-towards-infinity/images/bivium_tends_towards_infinity.JPG")
(define default-description
  "Dominik Zarzycki, textile artist and painter in Edinburgh: handwoven tapestries in handspun, naturally dyed wool, paintings, drawings and generative art.")

(define person-id (string-append site-url "/#person"))
(define website-id (string-append site-url "/#website"))

(define person
  (hasheq '@type "Person"
          '@id person-id
          'name site-name
          'url (string-append site-url "/")
          'jobTitle "Textile artist and painter"
          'description default-description
          'email "mailto:domino.zarzycki@gmail.com"
          'homeLocation (hasheq '@type "Place"
                                'address (hasheq '@type "PostalAddress"
                                                 'addressLocality "Edinburgh"
                                                 'addressCountry "GB"))
          'birthPlace (hasheq '@type "Place" 'name "Częstochowa, Poland")
          'alumniOf (hasheq '@type "EducationalOrganization"
                            'name "Jacek Malczewski School of Art in Częstochowa")
          'award (list "Alexander Graham Munro Travel Award (2023)")
          'knowsAbout (list "Tapestry" "Weaving" "Natural dyeing" "Hand spinning"
                            "Painting" "Watercolour" "Drawing" "Generative art")
          'sameAs (list "https://instagram.com/dominic_zarzycki"
                        "https://dominik-art.works/")))

;; ─── URLs ────────────────────────────────────────────────────────────
;; The published site links to clean URLs (/textiles/z-flow/, as GitHub
;; Pages serves them); the deploy sets SITE_CLEAN_URLS=1. Locally links
;; keep index.html, which Pollen's dev server needs.
(define clean? (equal? (getenv "SITE_CLEAN_URLS") "1"))

(define (clean-path href)
  (regexp-replace #rx"(^|/)index\\.html(#.*)?$" href "\\1\\2"))

(define (clean-href href)
  (if (and clean? (string-prefix? href "/")) (clean-path href) href))

;; 'textiles/z-flow/index.html → "/textiles/z-flow/" (always clean: the
;; canonical address is the published one)
(define (page-path here)
  (clean-path (string-append "/" (format "~a" here))))

(define (absolute path) (string-append site-url path))

;; ─── reading the page ────────────────────────────────────────────────
(define (meta metas key)
  (define v (hash-ref metas key #f))
  (and (string? v) (non-empty? v) v))

(define (non-empty? s) (regexp-match? #px"\\S" s))

(define (text-of x)
  (cond [(string? x) x]
        [(txexpr? x) (if (memq (get-tag x) '(script style)) ""
                         (string-append* (map text-of (get-elements x))))]
        [else ""]))

(define (squash s) (string-trim (regexp-replace* #px"\\s+" s " ")))

(define (find-all pred x)
  (cond [(not (txexpr? x)) empty]
        [(pred x) (cons x (append-map (lambda (e) (find-all pred e)) (get-elements x)))]
        [else (append-map (lambda (e) (find-all pred e)) (get-elements x))]))

(define (has-class? x cls)
  (and (txexpr? x)
       (member cls (string-split (or (attr-ref x 'class #f) "")))
       #t))

;; first paragraphs, cut at a word near 155 characters
(define (auto-description doc)
  (define paras (find-all (lambda (x) (eq? (get-tag x) 'p)) doc))
  (define text (squash (string-join (map text-of paras) " ")))
  (cond [(< (string-length text) 40) #f]
        [(<= (string-length text) 158) text]
        [else (string-append (regexp-replace #px"\\s+\\S*$" (substring text 0 155) "") "…")]))

;; images in the page: (original . alt), originals from data-full
(define (doc-images doc)
  (for/list ([img (find-all (lambda (x) (eq? (get-tag x) 'img)) doc)])
    (cons (or (attr-ref img 'data-full #f) (attr-ref img 'src ""))
          (attr-ref img 'alt ""))))

;; ─── <head> ──────────────────────────────────────────────────────────
(define (seo-head here metas doc)
  (define path (page-path here))
  (define url (absolute path))
  (define home? (equal? path "/"))
  (define title (or (meta metas 'title) site-name))
  (define full-title
    (or (meta metas 'seo-title)
        (if home? site-name (string-append title " — " site-name))))
  (define description (or (meta metas 'description) (auto-description doc) default-description))
  (define noindex? (equal? (meta metas 'noindex) "yes"))
  (define images (filter (lambda (i) (string-prefix? (car i) "/")) (doc-images doc)))
  (define-values (image-src image-alt)
    (cond [(meta metas 'image) => (lambda (i) (values i title))]
          [(pair? images) (values (car (first images)) (cdr (first images)))]
          [else (values default-image site-name)]))
  (define preview (resized image-src 1200))
  (define-values (pw ph) (image-size preview))
  (define tags
    (append
     (list `(title ,full-title)
           `(meta [[name "description"] [content ,description]])
           `(meta [[name "author"] [content ,site-name]]))
     (if noindex?
         (list `(meta [[name "robots"] [content "noindex, follow"]]))
         (list `(link [[rel "canonical"] [href ,url]])))
     (list `(meta [[property "og:type"] [content ,(if home? "profile" "website")]])
           `(meta [[property "og:site_name"] [content ,site-name]])
           `(meta [[property "og:locale"] [content "en_GB"]])
           `(meta [[property "og:title"] [content ,full-title]])
           `(meta [[property "og:description"] [content ,description]])
           `(meta [[property "og:url"] [content ,url]])
           `(meta [[property "og:image"] [content ,(absolute preview)]]))
     (if (and pw ph)
         (list `(meta [[property "og:image:width"] [content ,(~a pw)]])
               `(meta [[property "og:image:height"] [content ,(~a ph)]]))
         empty)
     (list `(meta [[property "og:image:alt"] [content ,(if (non-empty? image-alt) image-alt title)]])
           `(meta [[name "twitter:card"] [content "summary_large_image"]])
           `(meta [[name "twitter:title"] [content ,full-title]])
           `(meta [[name "twitter:description"] [content ,description]])
           `(meta [[name "twitter:image"] [content ,(absolute preview)]]))
     (if noindex?
         empty
         (list `(script [[type "application/ld+json"]]
                        ,(json-ld here path url title description metas doc
                                  (absolute (resized image-src 1600)) home?))))))
  (string-join (map ->html tags) "\n  "))

;; ─── structured data (schema.org JSON-LD) ────────────────────────────
(define (json-ld here path url title description metas doc image home?)
  (define page
    (hasheq '@type (cond [home? "ProfilePage"]
                         [(meta metas 'event-start) "WebPage"]
                         [(equal? (meta metas 'layout) "piece") "ItemPage"]
                         [(regexp-match? #rx"/$" path) "CollectionPage"]
                         [else "WebPage"])
            '@id url
            'url url
            'name title
            'description description
            'inLanguage "en"
            'isPartOf (hasheq '@id website-id)
            'primaryImageOfPage (hasheq '@type "ImageObject" 'url image)
            'about (hasheq '@id person-id)))
  (define page+
    (let* ([p (if home? (hash-set page 'mainEntity (hasheq '@id person-id)) page)]
           [crumbs (breadcrumbs here)])
      (if crumbs (hash-set p 'breadcrumb crumbs) p)))
  (define extra
    (cond [(meta metas 'event-start) (list (exhibition-event url title description metas image))]
          [(equal? (meta metas 'layout) "piece") (filter values (list (artwork doc url description image)))]
          [else empty]))
  (define graph
    (append (list (hasheq '@type "WebSite" '@id website-id 'url (string-append site-url "/")
                          'name site-name 'inLanguage "en" 'publisher (hasheq '@id person-id))
                  person
                  page+)
            extra))
  ;; "</" can't appear inside a <script>
  (string-replace (jsexpr->string (hasheq '@context "https://schema.org" '@graph graph))
                  "</" "<\\/"))

;; Home › Section › Page, from the page's folders
(define (breadcrumbs here)
  (define parts (string-split (format "~a" here) "/"))
  (define trail
    (let loop ([n 1] [acc empty])
      (if (> n (length parts))
          (reverse acc)
          (let* ([prefix (take parts n)]
                 [node (cond [(= n (length parts)) (format "~a" here)]
                             [else (string-append (string-join prefix "/") "/index.html")])])
            (loop (add1 n)
                  (if (and (not (equal? node "index.html"))
                           (not (member node acc))
                           (or (= n (length parts)) (file-exists? (build-path root (string-append node ".pm")))))
                      (cons node acc)
                      acc))))))
  (and (pair? trail)
       (hasheq '@type "BreadcrumbList"
               'itemListElement
               (for/list ([node (in-list (cons "index.html" trail))] [i (in-naturals 1)])
                 (hasheq '@type "ListItem"
                         'position i
                         'name (if (equal? node "index.html") "Home" (or (page-title node) node))
                         'item (absolute (page-path node)))))))

(define (page-title node)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (select-from-metas 'title (build-path root node))))

;; a piece page: title and the Year/Technique/... list of its £piece
(define (artwork doc url description image)
  (define piece (findf (lambda (x) (has-class? x "piece")) (find-all txexpr? doc)))
  (and piece
       (let* ([h1 (findf (lambda (x) (eq? (get-tag x) 'h1)) (get-elements piece))]
              [pairs (for/list ([d (find-all (lambda (x) (has-class? x "meta-pair")) piece)])
                       (define dt (findf (lambda (x) (and (txexpr? x) (eq? (get-tag x) 'dt))) (get-elements d)))
                       (define dd (findf (lambda (x) (and (txexpr? x) (eq? (get-tag x) 'dd))) (get-elements d)))
                       (cons (squash (text-of dt)) (squash (text-of dd))))]
              [field (lambda (k) (let ([p (assoc k pairs)]) (and p (cdr p))))]
              [medium (or (field "Medium") (field "Fibre"))])
         (for/fold ([h (hasheq '@type "VisualArtwork"
                               '@id (string-append url "#artwork")
                               'name (squash (text-of h1))
                               'url url
                               'image image
                               'description description
                               'creator (hasheq '@id person-id))])
                   ([kv (list (cons 'dateCreated (iso-date (field "Year")))
                              (cons 'artform (field "Technique"))
                              (cons 'artMedium medium)
                              (cons 'size (field "Dimensions")))])
           (if (cdr kv) (hash-set h (car kv) (cdr kv)) h)))))

;; "07.2025" → "2025-07", "2024" → "2024"
(define (iso-date s)
  (cond [(not s) #f]
        [(regexp-match #px"^(\\d{1,2})\\.(\\d{4})$" s)
         => (lambda (m) (format "~a-~a" (caddr m) (~r (string->number (cadr m)) #:min-width 2 #:pad-string "0")))]
        [(regexp-match #px"^\\d{4}$" s) s]
        [else #f]))

(define (exhibition-event url title description metas image)
  (define (m k) (meta metas k))
  (hasheq '@type "ExhibitionEvent"
          '@id (string-append url "#event")
          'name title
          'url url
          'description description
          'image image
          'startDate (m 'event-start)
          'endDate (or (m 'event-end) (m 'event-start))
          'eventStatus "https://schema.org/EventScheduled"
          'eventAttendanceMode "https://schema.org/OfflineEventAttendanceMode"
          'isAccessibleForFree #t
          'location (hasheq '@type "Place"
                            'name (or (m 'event-venue) "")
                            'address (hasheq '@type "PostalAddress"
                                             'streetAddress (or (m 'event-street) "")
                                             'addressLocality (or (m 'event-locality) "")
                                             'postalCode (or (m 'event-postcode) "")
                                             'addressCountry (or (m 'event-country) "GB")))
          'organizer (hasheq '@id person-id)
          'performer (hasheq '@id person-id)))

;; ─── sitemap.xml ─────────────────────────────────────────────────────
;; Every page in index.ptree (noindex pages excluded), with the date of
;; its last commit and the images it shows.
(define (sitemap-xml)
  (define nodes (pagetree->list (get-pagetree ptree-file)))
  (define entries
    (for/list ([node (in-list nodes)]
               #:unless (equal? (page-meta node 'noindex) "yes"))
      (define loc (absolute (page-path node)))
      (define lastmod (git-date (string-append (format "~a" node) ".pm")))
      (define imgs (page-images node))
      (string-append
       "  <url>\n    <loc>" (xml-escape loc) "</loc>\n"
       (if lastmod (string-append "    <lastmod>" lastmod "</lastmod>\n") "")
       (string-append*
        (for/list ([i (in-list imgs)])
          (string-append "    <image:image><image:loc>" (xml-escape (absolute i)) "</image:loc></image:image>\n")))
       "  </url>\n")))
  (string-append
   "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
   "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"\n"
   "        xmlns:image=\"http://www.google.com/schemas/sitemap-image/1.1\">\n"
   (string-append* entries)
   "</urlset>\n"))

(define (page-meta node key)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (select-from-metas key (build-path root (format "~a" node)))))

;; the pictures as shown on the page (the 1600px copies)
(define (page-images node)
  (with-handlers ([exn:fail? (lambda (_) empty)])
    (define doc (get-doc (build-path root (format "~a" node))))
    (remove-duplicates
     ;; whole pictures only: square crops (/thumbs/600f/…) are just previews
     (filter (lambda (s) (and (string-prefix? s "/") (not (regexp-match? #rx"^/thumbs/[0-9]+f/" s))))
             (for/list ([img (find-all (lambda (x) (eq? (get-tag x) 'img)) doc)])
               (attr-ref img 'src ""))))))

(define git (find-executable-path "git"))

(define (git-date file)
  (and git
       (let ([out (with-output-to-string
                    (lambda ()
                      (parameterize ([current-directory root]
                                     [current-error-port (open-output-nowhere)])
                        (system* git "log" "-1" "--format=%cs" "--" file))))])
         (and (regexp-match? #px"^\\d{4}-\\d{2}-\\d{2}" out) (substring out 0 10)))))

(define (xml-escape s)
  (for/fold ([s s]) ([p '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;"))])
    (string-replace s (car p) (cdr p))))
