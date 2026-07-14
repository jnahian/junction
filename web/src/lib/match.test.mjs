import assert from "node:assert/strict";
import { matches } from "./match.js";

// *.host/* — subdomains and the apex, at any depth
assert.ok(matches("https://mycorp.atlassian.net/browse/X-1", "*.atlassian.net/*"));
assert.ok(matches("atlassian.net/browse/X-1", "*.atlassian.net/*"));
assert.ok(!matches("https://atlassian.net.evil.com/x", "*.atlassian.net/*"));

// exact host + path prefix
assert.ok(matches("https://zoom.us/j/98765", "*.zoom.us/j/*"));
assert.ok(!matches("https://zoom.us/w/98765", "*.zoom.us/j/*"));
assert.ok(matches("https://app.clickup.com/t/86a", "app.clickup.com/*"));
assert.ok(!matches("https://clickup.com/t/86a", "app.clickup.com/*"));

// a bare host matches all of its subpaths, including the bare host itself
assert.ok(matches("https://reddit.com/r/macapps", "reddit.com/*"));
assert.ok(matches("reddit.com", "reddit.com"));

// an explicit ** behaves like a trailing * (the branch that replaced the lookbehind)
assert.ok(matches("https://mycorp.atlassian.net/browse/X-1", "*.atlassian.net/**"));
assert.ok(matches("https://zoom.us/j/98765", "*.zoom.us/j/**"));

// the catch-all
assert.ok(matches("https://anything.example/x", "*"));
assert.ok(!matches("", "*"));

console.log("match ok");
