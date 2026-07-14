const pills = Array.from(document.querySelectorAll(".fpill"));
const releases = Array.from(document.querySelectorAll(".release"));

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
  });
}

pills.forEach((p) => p.addEventListener("click", () => apply(p.dataset.f)));
apply("all");
