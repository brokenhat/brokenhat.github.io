# Pollen Portfolio Site

Static portfolio site built with [Pollen](https://docs.racket-lang.org/pollen/) (Racket). Every page is a small Racket program. Git history becomes a visible process journal for textile pieces.

## Prerequisites

- [Racket](https://racket-lang.org/) v9.3+
- Pollen: `raco pkg install --auto pollen`
- [ImageMagick](https://imagemagick.org/) (`magick` or `convert`) for tile thumbnails. Without it pages still build, using full-size images.

## Project structure

```
site/
  pollen.rkt               root config (setup, decoder, helpers)
  index.ptree               navigation hierarchy
  template.html.p           the one HTML template (layout chosen per page)

  index.html.pm             homepage: artist statement (English + Polish)
  cv.html.pm                CV

  in-a-zigzag-way/          solo exhibition page (+ images/)
  textiles/
    index.html.pm           the works, linking to their pages (£works)
    z-flow/                 one folder per piece: index.html.pm + images/
    the-rise-of-the-zigzag/   (main image, text, "Process & details")
    bivium-tends-towards-infinity/
    thawing/
    untitled-2024/
    blue-stem/
    sofreh-interlace/       also has a git-as-journal timeline
  studio/                   loom, wheel, natural dyeing
  paintings/  generative/  drawings/   galleries (+ images/)

  example/                  demo pages for the tags (not in the menu):
                            subpage, tiles, walk (Highland walk route)

  404.html.pm               "page not found" (GitHub Pages serves it)
  sitemap.xml.pp            builds sitemap.xml (lib/seo.rkt)
  robots.txt                points crawlers at the sitemap
  favicon.svg/.ico, apple-touch-icon.png

  lib/
    seo.rkt                 <head> tags, structured data, sitemap
    tags.rkt                all custom tag functions
    tiles.rkt               tile-grid tags
    thumbs.rkt              resized image copies (ImageMagick)
    git-timeline.rkt        reads git log per piece folder

  css/site.css              stylesheet
  css/tiles.css             tile-grid styles
  js/nav.js                 collapses the menu when it doesn't fit
  js/tile-grid.js           tile-grid pan/zoom + viewers
  images/                   images used by the example pages
  scripts/migrate.py        first content migration from the Flask DB
```

## Search engines (SEO)

`lib/seo.rkt` writes the `<head>` of every page: title, description, canonical address, link-preview tags (Open Graph, Twitter) and structured data (JSON-LD) that tells Google who you are and what each page shows. It also builds `sitemap.xml` (from `index.ptree`, with each page's images and last-commit date).

What each page can set, near the top:

```
£(define-meta title "Thawing")                        ← name in the menu
£(define-meta seo-title "Thawing, Woven Hanging (2025) — Dominik Zarzycki")
£(define-meta description "Thawing (2025), woven with cotton, sisal …")
£(define-meta image "/textiles/thawing/images/a.jpg")  ← link preview (else the page's first image)
£(define-meta noindex "yes")                          ← keep out of Google and the sitemap
```

- **Title:** without `seo-title` it's "title — Dominik Zarzycki". Keep it under 60 characters.
- **Description:** about 120–155 characters, saying what the page shows. Without one, the first paragraphs are used.
- **Alt text:** give every image an `#:alt` that describes it (`£fig["…" #:alt "Madder root dye bath"]{}`). It's how Google Images, and people using screen readers, know what's in it.
- **Piece pages** (`layout "piece"`) are described as artworks (VisualArtwork: name, year, technique, medium, size, image) from their `£piece` fields.
- **The exhibition page** is described as an event by its `event-start`, `event-end`, `event-venue`, `event-street`, `event-locality`, `event-postcode` metas.
- **New pages** go into `index.ptree` to be in the menu and the sitemap.
- The example pages and `404.html` are `noindex`.

Addresses: the published site uses clean URLs (`/textiles/thawing/`); the deploy sets `SITE_CLEAN_URLS=1` for that. Locally, links keep `index.html` because the dev server needs it. The site address (`site-url`) is set at the top of `lib/seo.rkt`, and in `robots.txt`.

Images: pages offer 400–1600px copies (`srcset`) so phones download small files, declare their size (no jumping while loading), and load the first picture first.

To check a page: https://search.google.com/test/rich-results and https://pagespeed.web.dev/



This project uses `£` as the Pollen command character (instead of the default `◊`).

To write a literal £ sign in content, double it: `££`.

## Available tags

### Page structure

| Tag | Usage |
|-----|-------|
| `£title{Page Title}` | Main page heading |
| `£section-intro{text}` | Intro paragraph block with smart typography |

### Piece pages

```
£piece[#:title "Sofreh Interlace"
       #:year "2023"
       #:technique "mixed media tapestry"
       #:fibre "wool, silk on cotton warp"
       #:medium "watercolour, pigments, paper, wool, silk"
       #:dimensions "100cm x 110cm"
       #:exhibition "RSW 143rd Annual Exhibition"
       #:award "Some Award"
       #:status "finished"]{

Body content here.

}
```

All `#:` keyword arguments are optional.

### Images

| Tag | Usage |
|-----|-------|
| `£gallery{ £fig[...]{} ... }` | Grid of figures |
| `£fig["path.jpg" #:alt "desc"]{caption}` | Figure with lazy-loaded image |
| `£image["path.jpg" #:alt "desc" #:class "hero"]{}` | Standalone image |
| `£works{ £work[...] ... }` | A section's pieces as square thumbnails linking to their pages |
| `£work["/textiles/x/index.html" #:image "/textiles/x/images/a.jpg" #:title "X" #:year "2025"]` | One piece in `£works` |

Write image paths from the site root (`/paintings/images/a.jpg`): pages then show a 1600px copy (see Image sizes below) and the viewer's loupe and full view load the original. Relative paths still work but always serve the original file.

The Example section (`example/`) is not in `index.ptree`, so it isn't in the menu; its pages still build and work at `/example/…`.

### Tile grid pages

A tile page shows your work as squares on a grid you can drag around and zoom, like blog-tile. The site menu stays at the top; the grid fills the rest of the page.

See it working: `example/tiles.html.pm` → http://localhost:8080/example/tiles.html

#### Make a new tile page

1. Create a file, e.g. `textiles/grid.html.pm`, starting with:

   ```
   #lang pollen
   £(define-meta layout "tiles")
   £(define-meta title "Grid")

   £tile-grid{

   }
   ```

2. Put tiles between the `£tile-grid{` and `}` lines (see below).

3. Add the page to `index.ptree` under its section so it shows in the menu:

   ```
   textiles/index.html
     textiles/grid.html
   ```

4. Save and reload the browser.

#### Kinds of tile

**Image** — give it `#:image`:

```
£tile[#:x 0 #:y 0 #:title "Sofreh Interlace" #:image "/images/sofreh.png"]{}
```

**Image with text** — same, with text inside `{ }`. Clicking it shows the text beside the picture (on phones and portrait tablets: picture on top, text below). The ⤢ button or a click on the picture opens it full screen.

```
£tile[#:x 1 #:y 0 #:title "Studio" #:image "/images/studio.jpg"]{
Text shown beside the image.
}
```

**Text** — no image, just text. Blank lines start new paragraphs; links work.

```
£tile[#:x 0 #:y 1 #:title "On the loom"]{
First paragraph.

Second paragraph with a £link["/cv.html"]{link}.
}
```

**Sketchbook** — a list of pages. The first page is the cover.

```
£tile[#:x -1 #:y 0 #:title "Sketchbook 2024"]{
£sketch-page["/images/page1.jpg"]
£sketch-page["/images/page2.jpg"]
£sketch-page["/images/page3.jpg"]
}
```

#### Where a tile goes

`#:x` and `#:y` are the tile's square on the grid. `x` goes right, `y` goes **up**:

```
          y=1
  x=-1   [0,0]   x=1
          y=-1
```

Empty squares next to your tiles are drawn automatically. To move a tile, change its numbers; to remove it, delete its line.

#### Arrows and paths

An arrow sits on an empty square and points the way to another tile, as in blog-tile. Put arrows inside `£tile-grid{ }` with the tiles:

```
£arrow[#:x 1 #:y 0 #:dir "right"]      ← leads to the next tile to its right
£arrow[#:x 1 #:y -2 #:to "-1 0"]       ← leads to the tile at -1, 0 (anywhere)
£arrow[#:x -1 #:y 1 #:dir "up" #:to "0 1"]
```

- `#:dir` is `up`, `down`, `left` or `right`. Without `#:to`, the arrow leads to the first tile that way (straight in line if there is one, otherwise the nearest one ahead).
- `#:to "x y"` picks the tile it leads to. With `#:to` you can leave out `#:dir`: it then points along the longer distance.
- Clicking an arrow glides the grid to its tile.

**Paths.** A tile directly behind an arrow's tail is linked to the arrow's tile: tile → arrow → tile. Chain them to make a route through the grid:

```
[A] ▶ [B]        £arrow[#:x 1 #:y 0 #:dir "right"]   A → B
       ▼         £arrow[#:x 1 #:y -1 #:dir "down"]   B → C
      [C]
```

Along a path:
- With a tile selected, the arrow key in the arrow's direction follows it.
- Every viewer (text, image, lightbox, sketchbook) shows **← previous · next →** buttons at the top, so visitors can go through the route without closing anything. The ← → keys do the same, except in a sketchbook, where they turn pages.

`example/tiles.html.pm` has a route through all five of its tiles. `example/walk.html.pm` (Example → Highland walk) is a fuller one, with a map of the route in its comments: turns, an arrow that skips an empty square, a long jump with `#:to`, a loop back to the start, and a tile deliberately left off the route. An arrow with nothing to lead to is drawn faded.

#### Optional settings

| Setting | What it does | Example |
|---------|--------------|---------|
| `#:title` | Name shown on hover and in the viewer | `#:title "Blue Stem"` |
| `#:caption` | Short line under the title | `#:caption "detail"` |
| `#:date` | Small label at the top of the tile | `#:date "2024"` |
| `#:focus` | Which part of the image the square shows | `#:focus "30% 50%"` |
| `#:zoom` | Zoom into the image inside the square | `#:zoom 1.3` |
| `#:bg` | Tile background colour | `#:bg "#eee"` |

#### Using the page

| To… | Mouse / keyboard | Phone |
|-----|------------------|-------|
| Move around | Drag, or arrow keys | Drag |
| Zoom | Scroll wheel, `+` `-`, or the buttons | Pinch |
| See everything | `0` or the ⤢ button | ⤢ button |
| Open a tile | Click, or Enter | Tap |
| Close a tile | `Esc`, × or click outside | × or, at the end of it, a quick swipe up (a slow drag springs back unless pulled ~⅓ of the screen) |

Images open full screen: scroll or `+` `-` to zoom, `1` for actual size, `0` to fit, drag to look around, `Esc` to close; on a phone pinch to zoom and swipe down to close. Sketchbooks open as a two-page book (arrow keys or swipe to turn pages); click a page to enlarge it.

#### Image sizes

You only ever point tiles at your original images. When the page renders, `lib/thumbs.rkt` makes smaller copies in `thumbs/` (ignored by git, rebuilt by CI):

| Copy | Used for |
|------|----------|
| `thumbs/400f/…`, `thumbs/800f/…` | The square tile (800 on sharp/retina screens) |
| `thumbs/1600/…` | Side-by-side view, full-screen view, sketchbook pages |
| the original | Only when you press `1:1` |

Copies are remade when the original changes. Image paths must start with `/` (e.g. `/images/a.jpg`) to be resized. If you edit files in `lib/`, run `raco pollen reset` so pages re-render.

#### Files

| File | Role |
|------|------|
| `lib/tiles.rkt` | The `£tile-grid`, `£tile`, `£sketch-page`, `£arrow` tags |
| `lib/thumbs.rkt` | Makes the resized image copies |
| `template.html.p` | With `layout "tiles"`: full-height grid, loads the tile CSS/JS |
| `css/tiles.css` | Look of tiles and viewers |
| `js/tile-grid.js` | Dragging, zooming, opening tiles |

### Process journal

| Tag | Usage |
|-----|-------|
| `£process-note[#:date "2023-09-15"]{text}` | Timestamped note |
| `£git-timeline["textiles/sofreh-interlace"]` | Auto-generated timeline from git commits |

### CV

| Tag | Usage |
|-----|-------|
| `£cv-section["Education"]{entries}` | CV section with heading |
| `£cv-entry[#:year "2023"]{description}` | Year + description row |
| `£exhibition["Show" #:year "2024" #:venue "RSA"]` | Exhibition entry |
| `£award["Award Name" #:year "2023"]` | Award entry |

### Typography

| Tag | Usage |
|-----|-------|
| `£lede{text}` | Lead paragraph |
| `£aside{text}` | Side note |
| `£smallcaps{text}` | Small caps span |
| `£blockquote{text}` | Block quote |
| `£link["url"]{text}` | Internal link |
| `£ext-link["url"]{text}` | External link (opens in new tab) |

## Adding content

### New section

1. Create `newsection/index.html.pm`:
   ```
   #lang pollen
   £(define-meta title "New Section")

   £title{New Section}

   £section-intro{Description here.}
   ```
2. Add to `index.ptree`:
   ```
   newsection/index.html
   ```

### New piece (subpage)

1. Create the `.pm` file (or folder with `index.html.pm` for pieces with process images)
2. Add to `index.ptree` indented under its parent section

### New textile piece with git-as-journal

```bash
mkdir -p site/textiles/new-piece/images
# Write site/textiles/new-piece/index.html.pm with £piece tag
# Add to index.ptree indented under textiles/index.html
cp ~/photo.jpg site/textiles/new-piece/images/01-concept.jpg
git add site/textiles/new-piece/ && git commit -m "sketch: initial concept for new-piece"
```

### Sub-subpages

Nest deeper in `index.ptree`:
```
textiles/index.html
  textiles/sofreh-interlace/index.html
    textiles/sofreh-interlace/studies.html
```

## Commit conventions for process journal

Each commit to a piece folder becomes a timeline entry on the published site.

| Prefix | Meaning |
|--------|---------|
| `sketch:` | Initial concept or sketch |
| `swatch:` | Colour/material sample |
| `warp:` | Warping the loom |
| `weave:` | Weaving progress |
| `note:` | Written reflection |
| `photo:` | Process photograph |
| `finish:` | Completion or finishing step |

Example: `git commit -m "warp: cotton warp set up, 12 epi"`

## Building locally

Development server (live reload):
```bash
cd site
raco pollen start
# → http://localhost:8080
```

Static render:
```bash
cd site
raco pollen render -r .
```

## Publishing

Push to `main` branch. GitHub Actions will:
1. Check out the full git history (for `£git-timeline`)
2. Install Racket + Pollen
3. Render all pages
4. Deploy to GitHub Pages

The site is live at https://brokenhat.github.io/ (repository `brokenhat/brokenhat.github.io`).

## Page layouts

Every page uses `template.html.p`. Pick a layout near the top of the page:

```
£(define-meta layout "piece")   ← a single work (adds class content--piece)
£(define-meta layout "tiles")   ← a tile grid page (full-height grid + tile scripts)
```

Without a `layout` line the page is a plain page. This works the same at any folder depth.
