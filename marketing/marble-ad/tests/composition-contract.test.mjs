import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const frame = readFileSync(new URL("../frame.md", import.meta.url), "utf8");
const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const hyperframesConfig = JSON.parse(readFileSync(new URL("../hyperframes.json", import.meta.url), "utf8"));

assert.match(html, /data-composition-id="main"/);
assert.match(html, /data-width="1080"/);
assert.match(html, /data-height="1920"/);
assert.match(html, /data-duration="31\.25"/);
assert.match(html, /window\.__timelines\["main"\]\s*=\s*tl/);

const sceneIds = [...html.matchAll(/<section[^>]+id="(scene-\d+)"/g)].map((match) => match[1]);
assert.deepEqual(sceneIds, ["scene-1", "scene-2", "scene-3", "scene-4", "scene-5"]);

for (const banned of ["repeat: -1", "Math.random", "Date.now", "setTimeout", "setInterval", "requestAnimationFrame", "async ", "<br"]) {
  assert.equal(html.includes(banned), false, `banned pattern found: ${banned}`);
}

assert.match(html, /Garmin via Health/);
assert.match(html, /assets\/logos\/apple-health\.svg/);
assert.match(html, /assets\/logos\/garmin\.svg/);
assert.match(html, /assets\/logos\/strava\.svg/);
assert.doesNotMatch(html, /direct Garmin sync/i);
assert.match(html, /No Marble server/);
assert.match(html, /Stored on iPhone/);

const variablesBlock = frame.match(/Colors:[\s\S]*?Typography:/)?.[0] ?? "";
const approved = new Set([...variablesBlock.matchAll(/#[0-9a-fA-F]{6}/g)].map((match) => match[0].toLowerCase()));
const used = [...html.matchAll(/#[0-9a-fA-F]{6}/g)].map((match) => match[0].toLowerCase());
const unexpected = [...new Set(used.filter((color) => !approved.has(color)))];
assert.deepEqual(unexpected, []);

for (let i = 1; i <= 5; i += 1) {
  assert.match(html, new RegExp(`#scene-${i} \\.`, "g"));
}

assert.match(pkg.scripts["hf:render:draft"], /scripts\/render-to-ssd\.mjs draft/);
assert.match(pkg.scripts["hf:render:final"], /scripts\/render-to-ssd\.mjs final/);
assert.doesNotMatch(pkg.scripts["hf:render:draft"], /--output renders\//);
assert.doesNotMatch(pkg.scripts["hf:render:final"], /--output renders\//);
assert.equal(hyperframesConfig.paths.renders, "/Volumes/PortableSSD/03_DELIVERABLES/Marble");

console.log("composition contract passed");
