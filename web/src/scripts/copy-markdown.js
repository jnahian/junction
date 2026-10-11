// "Copy Markdown" on a use-case page: copies /use-cases/<slug>.md. The clipboard
// gets a promise rather than awaited text, because Safari only allows a clipboard
// write inside the click itself and the fetch would outlive it.
document.querySelectorAll("[data-copy-md]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const text = fetch(btn.dataset.copyMd)
      .then((r) => r.text())
      .then((t) => new Blob([t], { type: "text/plain" }));
    const copied = window.ClipboardItem
      ? navigator.clipboard.write([new ClipboardItem({ "text/plain": text })])
      : text.then((b) => b.text()).then((t) => navigator.clipboard.writeText(t));
    copied.then(() => {
      const old = btn.textContent;
      btn.classList.add("done");
      btn.textContent = "Copied";
      setTimeout(() => {
        btn.classList.remove("done");
        btn.textContent = old;
      }, 1500);
    });
  });
});
