import { events } from "../lib/diagram.js";

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const packets = document.getElementById("packets");
const jglow = document.getElementById("jglow");
const jlogo = document.getElementById("jlogo");

const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function tween(dur, cb) {
  return new Promise((res) => {
    const start = performance.now();
    (function frame(now) {
      const t = Math.min(1, (now - start) / dur);
      cb(easeInOut(t));
      if (t < 1) requestAnimationFrame(frame);
      else res();
    })(start);
  });
}

function makePacket(color) {
  const c = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  c.setAttribute("r", "5.5");
  c.setAttribute("fill", color);
  c.setAttribute("filter", "url(#glow)");
  c.setAttribute("opacity", "0");
  packets.appendChild(c);
  return c;
}

function ride(pathId, color, dur) {
  const path = document.getElementById(pathId);
  const len = path.getTotalLength();
  const c = makePacket(color);
  return tween(dur, (e) => {
    const p = path.getPointAtLength(e * len);
    c.setAttribute("cx", p.x);
    c.setAttribute("cy", p.y);
    const o = e < 0.12 ? e / 0.12 : e > 0.88 ? (1 - e) / 0.12 : 1;
    c.setAttribute("opacity", Math.max(0, Math.min(1, o)));
  }).then(() => c.remove());
}

function setActiveChip(i, on) {
  const g = document.getElementById("chip" + i);
  g.classList.toggle("chip-active", on);
  const box = g.querySelector(".chip-box");
  box.setAttribute("stroke", on ? "var(--line-strong)" : "var(--line)");
  box.setAttribute("fill", on ? "rgba(17,27,43,.95)" : "rgba(17,27,43,.6)");
}

function pulseJunction(color) {
  jglow.setAttribute("fill", color);
  const start = performance.now();
  (function anim(now) {
    const t = Math.min(1, (now - start) / 520);
    const scale = 1 + Math.sin(t * Math.PI) * 0.14;
    jlogo.setAttribute("transform", `translate(${500 - 500 * scale} ${280 - 280 * scale}) scale(${scale})`);
    jglow.setAttribute("opacity", 0.55 + Math.sin(t * Math.PI) * 0.4);
    if (t < 1) requestAnimationFrame(anim);
    else {
      jlogo.setAttribute("transform", "");
      jglow.setAttribute("opacity", ".55");
      jglow.setAttribute("fill", "url(#jgrad)");
    }
  })(start);
}

const litDest = (i, on) => document.getElementById("dest" + i).classList.toggle("lit", on);
const hotRule = (i, on) => document.querySelector(`.rule[data-rule="${i}"]`)?.classList.toggle("hot", on);

async function runEvent(ev) {
  setActiveChip(ev.chip, true);
  await sleep(140);
  await ride(ev.inPath, "#c7d2e6", 780); // link → junction, still unrouted
  pulseJunction(ev.color);
  await sleep(90);
  hotRule(ev.rule, true);
  await ride(ev.dPath, ev.color, 780); // junction → destination, in the rule's color
  litDest(ev.dest, true);
  await sleep(1050);
  setActiveChip(ev.chip, false);
  litDest(ev.dest, false);
  hotRule(ev.rule, false);
  await sleep(360);
}

if (reduce) {
  // one event frozen mid-route, so the diagram still reads as a diagram
  const ev = events[1];
  setActiveChip(ev.chip, true);
  litDest(ev.dest, true);
  hotRule(ev.rule, true);
  const path = document.getElementById(ev.dPath);
  const pt = path.getPointAtLength(path.getTotalLength() * 0.62);
  const c = makePacket(ev.color);
  c.setAttribute("cx", pt.x);
  c.setAttribute("cy", pt.y);
  c.setAttribute("opacity", "1");
} else {
  (async () => {
    for (let i = 0; ; i = (i + 1) % events.length) await runEvent(events[i]);
  })();
}
