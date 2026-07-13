// Scroll-spy: highlight the nav link whose section is in view.
(function () {
  const links = document.querySelectorAll('.site-nav nav a[href^="#"]');
  if (!links.length) return;

  const map = new Map();
  links.forEach((a) => {
    const id = a.getAttribute('href').slice(1);
    const el = document.getElementById(id);
    if (el) map.set(el, a);
  });

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        const link = map.get(e.target);
        if (!link) return;
        if (e.isIntersecting) {
          links.forEach((l) => l.classList.remove('is-active'));
          link.classList.add('is-active');
        }
      });
    },
    { rootMargin: '-40% 0px -55% 0px', threshold: 0 }
  );

  map.forEach((_, el) => io.observe(el));
})();
