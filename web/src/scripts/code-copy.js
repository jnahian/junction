document.querySelectorAll(".copy-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    if (!navigator.clipboard) return;
    const text = btn.closest(".code").querySelector("code").innerText;
    navigator.clipboard.writeText(text).then(() => {
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
