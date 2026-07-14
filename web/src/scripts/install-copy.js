document.querySelectorAll(".term[data-copy]").forEach((term) => {
  term.addEventListener("click", () => {
    if (!navigator.clipboard) return;
    navigator.clipboard.writeText(term.dataset.copy).then(() => {
      const cp = term.querySelector(".cp");
      const old = cp.textContent;
      term.classList.add("copied");
      cp.textContent = "COPIED";
      setTimeout(() => {
        term.classList.remove("copied");
        cp.textContent = old;
      }, 1600);
    });
  });
});
