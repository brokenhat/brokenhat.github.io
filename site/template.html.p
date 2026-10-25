<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>£(or (select-from-metas 'title here) "Dominik Zarzycki")</title>
  <script>document.documentElement.classList.add('js')</script>
  <link rel="stylesheet" href="/css/site.css">
  £(if (equal? (page-layout metas) "tiles") "<link rel=\"stylesheet\" href=\"/css/tiles.css\">" "")
</head>
<body class="page--£(page-layout metas)">
  <header>
    <nav class="site-nav" aria-label="Main">
      <a class="site-name" href="/">Dominik Zarzycki</a>
      <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-menu"><span class="nav-toggle__label">Menu</span><span class="nav-toggle__icon" aria-hidden="true"></span></button>
      <ul id="site-menu">
        £(apply string-append (map ->html (site-nav-items here)))
      </ul>
    </nav>
  </header>

  <main class="content--£(page-layout metas)">
    £(apply string-append (map ->html (cdr doc)))
  </main>

  <footer>
    <p>£(copyright-year) Dominik Zarzycki</p>
  </footer>
  <script src="/js/nav.js" defer></script>
  <script src="/js/viewer.js" defer></script>
  £(if (equal? (page-layout metas) "tiles") "<script src=\"/js/tile-grid.js\" defer></script>" "")
</body>
</html>
