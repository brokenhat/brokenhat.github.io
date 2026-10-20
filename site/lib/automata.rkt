#lang racket/base
(require txexpr)

;; Woven Automata page: the controls, viewer and panels around the
;; Prolog generator. js/woven-automata.js runs woven_automata.pl in the
;; browser (js/woven-worker.js) and fills these in.

(provide woven-automata-app)

(define modes
  '(("random" "random")
    ("good" "search + evolve")
    ("crystalline" "crystalline")
    ("life" "life")
    ("uniform" "uniform rule")))

;; Wolfram elementary CA rules offered by name; any 0–255 via "other"
(define ca-rules
  '(("auto" "auto (by kind)")
    ("none" "none")
    ("30" "30 chaos")
    ("45" "45")
    ("54" "54")
    ("60" "60")
    ("73" "73")
    ("90" "90 sierpinski")
    ("105" "105")
    ("110" "110 gliders")
    ("150" "150")
    ("184" "184 traffic")
    ("other" "other…")))

(define (options pairs)
  (for/list ([p (in-list pairs)])
    `(option [[value ,(car p)]] ,(cadr p))))

(define (row label control)
  `(label [[class "wa-row"]] (span ,label) ,control))

(define (number name min max value)
  `(input [[type "number"] [name ,name] [min ,min] [max ,max] [step "1"]
           [value ,value] [inputmode "numeric"] [required ""]]))

(define (button act label [aria #f])
  `(button [[type "button"] [data-act ,act] ,@(if aria `([aria-label ,aria]) '())] ,label))

(define (woven-automata-app)
  `(div [[class "wa"] [data-decoded "true"]]
        (form [[class "wa-controls"] [aria-label "Design settings"]]
              ,(row "kind" `(select [[name "mode"]] ,@(options modes)))
              ,(row "warp" (number "width" "20" "200" "80"))
              ,(row "picks" (number "picks" "20" "1000" "500"))
              ,(row "bobbins" (number "bobbins" "2" "26" "8"))
              ,(row "cap" (number "max" "2" "100" "20"))
              ,(row "borders" `(select [[name "border"]]
                                       (option [[value "slit"]] "slit")
                                       (option [[value "interlock"]] "interlock")))
              ,(row "ca rule" `(select [[name "ca"]] ,@(options ca-rules)))
              (label [[class "wa-row"] [data-rule ""] [hidden ""]]
                     (span "rule no.")
                     ,(number "rule" "0" "255" "30"))
              (div [[class "wa-row"]]
                   (label [[for "wa-seed"]] "seed")
                   (div [[class "wa-pair"]]
                        (input [[id "wa-seed"] [type "number"] [name "seed"] [min "1"] [max "999999"]
                                [step "1"] [value "1"] [inputmode "numeric"] [required ""]])
                        ,(button "seed" "new")))
              (div [[class "wa-pair"]]
                   (button [[type "submit"] [class "wa-go"]] "generate")
                   (button [[type "button"] [data-act "cancel"] [hidden ""]] "cancel")
                   (button [[type "button"] [data-act "pdf"] [disabled ""]] "pdf"))
              (p [[class "wa-status"] [role "status"] [aria-live "polite"]]
                 "Needs JavaScript (runs a Prolog program)."))
        (section [[class "wa-viewer"] [aria-label "Design"]]
                 (div [[class "wa-toolbar"]]
                      ,(button "prev" "↓" "Previous pick (down)")
                      (span [[class "wa-pickno"]] "–")
                      ,(button "next" "↑" "Next pick (up)")
                      (input [[type "range"] [class "wa-slider"] [min "1"] [max "1"] [value "1"]
                              [aria-label "Pick to follow"]])
                      ,(button "zoom-out" "−" "Zoom out")
                      ,(button "zoom-fit" "fit" "Fit width")
                      ,(button "zoom-in" "+" "Zoom in"))
                 ;; the canvas draws only what's in view; the transparent
                 ;; scroller on top provides scrolling, clicks and keys
                 (div [[class "wa-stage"]]
                      (canvas [[class "wa-canvas"] [aria-hidden "true"]])
                      (div [[class "wa-scroller"] [tabindex "0"] [role "application"]
                            [aria-label "Woven design. Click a row, or use the up and down arrow keys, to choose the pick to follow."]]
                           (div [[class "wa-spacer"]])))
                 (p [[class "wa-hover"] [aria-hidden "true"]] " ")
                 (ul [[class "wa-legend"]]
                     (li (span [[class "wa-swatch"] [data-v "1"]]) "black full")
                     (li (span [[class "wa-swatch"] [data-v "3"]]) "black half")
                     (li (span [[class "wa-swatch"] [data-v "2"]]) "white full")
                     (li (span [[class "wa-swatch"] [data-v "4"]]) "white half")
                     (li (span [[class "wa-swatch"] [data-v "0"]]) "bare")))
        (section [[class "wa-pick"] [aria-label "Pick to follow"]]
                 (h2 [[class "wa-pick-title"]] "pick")
                 (ol [[class "wa-steps"]]))
        (details [[class "wa-rules"]]
                 (summary "rules + procedure")
                 (pre [[class "wa-rules-text"]]))))
