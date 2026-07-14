import assert from "node:assert/strict";
import { version, releases, rewriters } from "./repo.js";

// version comes from App/Info.plist, the file a release actually bumps
assert.match(version(), /^v\d+\.\d+\.\d+$/);

const all = releases();
assert.ok(all.length >= 10, "every CHANGELOG.md section should parse");
const shipped = all.filter((r) => !r.unreleased);
assert.equal(shipped[0].version, version(), "newest shipped changelog entry must match App/Info.plist");

for (const release of shipped) {
  assert.match(release.version, /^v\d+\.\d+\.\d+$/);
  assert.match(release.date, /^[A-Z][a-z]{2} \d{1,2}, \d{4}$/, `bad date on ${release.version}`);
  assert.ok(release.changes.length > 0, `${release.version} has no entries`);
  for (const change of release.changes) {
    assert.ok(["add", "chg", "fix"].includes(change.type), `${release.version}: bad type ${change.type}`);
    assert.ok(change.body.length > 0);
  }
}

const { count, apps } = rewriters();
assert.equal(count, 17);
assert.ok(apps.includes("Slack") && apps.includes("Zoom"));
assert.equal(new Set(apps).size, apps.length, "app list should be deduped");

console.log("repo ok");
