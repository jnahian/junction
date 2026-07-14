import { matches } from "../lib/match.js";

const rows = Array.from(document.querySelectorAll("#mRules .mrule"));
const input = document.getElementById("urlIn");
const result = document.getElementById("mResult");

function run() {
  const hit = rows.findIndex((row) => matches(input.value, row.dataset.pat));
  rows.forEach((row, i) => row.classList.toggle("match", i === hit));
  const win = rows[hit];
  result.innerHTML = win ? `→ opens in <b style="color:${win.dataset.color}">${win.dataset.dst}</b>` : "";
}

input.addEventListener("input", run);
run();
