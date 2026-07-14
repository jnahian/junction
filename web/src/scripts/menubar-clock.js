// The strip is pretending to be your menu bar, so it shows your actual clock.
// Server-rendered value in landing.json stays as the pre-hydration fallback.
const clock = document.getElementById("clock");

function render() {
  const now = new Date();
  const weekday = now.toLocaleDateString(undefined, { weekday: "short" });
  const time = now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  clock.textContent = `${weekday} ${now.getDate()} · ${time}`;

  // tick on the minute boundary, not every 60s from load
  const untilNextMinute = 60_000 - (now.getSeconds() * 1000 + now.getMilliseconds());
  setTimeout(render, untilNextMinute);
}

render();
