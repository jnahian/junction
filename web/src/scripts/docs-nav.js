/* scrollspy */
const links = Array.from(document.querySelectorAll('.sidebar a[href^="#"]'));
const byId = Object.fromEntries(links.map((a) => [a.getAttribute("href").slice(1), a]));

function setActive(id) {
  links.forEach((a) => a.classList.remove("active"));
  byId[id]?.classList.add("active");
}

const spy = new IntersectionObserver(
  (entries) => entries.forEach((e) => e.isIntersecting && setActive(e.target.id)),
  { rootMargin: "-60px 0px -74% 0px", threshold: 0 }
);
document.querySelectorAll(".doc section").forEach((s) => spy.observe(s));
setActive("overview");

/* mobile drawer */
const sidebar = document.getElementById("sidebar");
const scrim = document.getElementById("scrim");
const menuBtn = document.getElementById("menuBtn");

function closeNav() {
  sidebar.classList.remove("open");
  scrim.classList.remove("show");
}

menuBtn?.addEventListener("click", () => {
  if (sidebar.classList.contains("open")) closeNav();
  else {
    sidebar.classList.add("open");
    scrim.classList.add("show");
  }
});
scrim?.addEventListener("click", closeNav);
sidebar.addEventListener("click", (e) => {
  if (e.target.tagName === "A") closeNav();
});
