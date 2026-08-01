const pills = Array.from(document.querySelectorAll(".fpill"));
const releases = Array.from(document.querySelectorAll(".release"));
// filtering can empty a whole release; its TOC entry has to go with it
const tocLinks = Object.fromEntries(
  Array.from(document.querySelectorAll(".cl-toc a")).map((a) => [a.getAttribute("href").slice(1), a])
);

function apply(filter) {
  pills.forEach((p) => p.classList.toggle("active", p.dataset.f === filter));
  releases.forEach((rel) => {
    let shown = 0;
    rel.querySelectorAll(".rel-list li").forEach((li) => {
      const show = filter === "all" || li.dataset.type === filter;
      li.style.display = show ? "" : "none";
      if (show) shown++;
    });
    rel.style.display = shown ? "" : "none";
    tocLinks[rel.id]?.classList.toggle("hidden", !shown);
  });
}

pills.forEach((p) => p.addEventListener("click", () => apply(p.dataset.f)));
apply("all");
