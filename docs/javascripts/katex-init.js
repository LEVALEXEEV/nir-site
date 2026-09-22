// KaTeX грузится с самого сайта (assets/katex), без CDN. Material подменяет страницы
// без перезагрузки (instant loading не включён, но document$ есть всегда) — рендер на каждую.
document$.subscribe(({ body }) => {
  renderMathInElement(body, {
    delimiters: [
      { left: "$$", right: "$$", display: true },
      { left: "$", right: "$", display: false },
      { left: "\\(", right: "\\)", display: false },
      { left: "\\[", right: "\\]", display: true },
    ],
  });
});
