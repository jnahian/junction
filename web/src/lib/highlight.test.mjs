import assert from "node:assert/strict";
import { highlightJson } from "./highlight.js";

assert.equal(
  highlightJson('{ "match": "*.figma.com" }'),
  '<span class="tk-pun">{</span> <span class="tk-key">"match"</span><span class="tk-pun">:</span> <span class="tk-str">"*.figma.com"</span> <span class="tk-pun">}</span>'
);
assert.equal(highlightJson('["a"]'), '<span class="tk-pun">[</span><span class="tk-str">"a"</span><span class="tk-pun">]</span>');
assert.equal(highlightJson('"<b>"'), '<span class="tk-str">"&lt;b&gt;"</span>');

console.log("highlight ok");
