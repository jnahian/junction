/* scrollspy. Not an IntersectionObserver like the docs sidebar: releases are short,
   so several sit in any sensible band at once and entry order decides the winner.
   Geometry instead — the current release is the last one whose top passed the chrome. */
const links = Array.from(document.querySelectorAll(".cl-toc a"));
const byId = Object.fromEntries(links.map((a) => [a.getAttribute("href").slice(1), a]));
const releases = Array.from(document.querySelectorAll(".release"));

const LINE = 120; // just below the sticky chrome (--chrome-h is 86)
let pinned = null; // a clicked entry stays lit until the reader scrolls themselves

function setActive(id) {
  links.forEach((a) => a.classList.remove("active"));
  byId[id]?.classList.add("active");
}

function sync() {
  if (pinned) return setActive(pinned);

  const shown = releases.filter((r) => r.style.display !== "none");
  let current = shown[0];
  for (const r of shown) if (r.getBoundingClientRect().top <= LINE) current = r;

  // the oldest releases share the final screenful and can never reach the line
  const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
  if (atBottom) current = shown[shown.length - 1];

  if (current) setActive(current.id);
}

// clicking is explicit intent: light the target even where scrolling can't reach it
links.forEach((a) =>
  a.addEventListener("click", () => {
    pinned = a.getAttribute("href").slice(1);
    setActive(pinned);
  })
);
// ...but a scroll the reader started hands control back to geometry
["wheel", "touchmove", "keydown"].forEach((ev) =>
  addEventListener(ev, () => (pinned = null), { passive: true })
);

let queued = false;
addEventListener(
  "scroll",
  () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      sync();
    });
  },
  { passive: true }
);

// filtering hides releases and reflows the page without ever firing a scroll event
document.getElementById("filters")?.addEventListener("click", () => {
  pinned = null;
  requestAnimationFrame(sync);
});

sync();
