import { mkdirSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";

const SSD_MOUNT = "/Volumes/PortableSSD";
const OUTPUT_ROOT = process.env.MARBLE_VIDEO_OUTPUT_ROOT || `${SSD_MOUNT}/03_DELIVERABLES/Marble`;

const profiles = {
  draft: {
    quality: "draft",
    relativeOutput: "drafts/marble-ad-song-draft.mp4",
  },
  final: {
    quality: "high",
    relativeOutput: "marble-ad-song-final.mp4",
  },
};

const kind = process.argv[2] || "final";
const requestedArgs = process.argv.slice(3);
const dryRun = requestedArgs.includes("--dry-run");
const extraArgs = requestedArgs.filter((arg) => arg !== "--dry-run");
const profile = profiles[kind];

if (!profile) {
  console.error(`Unknown render profile "${kind}". Use "draft" or "final".`);
  process.exit(1);
}

const date = process.env.VIDEO_OUTPUT_DATE || getPacificDate();
const outputDir = `${OUTPUT_ROOT}/${date}`;
const outputPath = `${outputDir}/${profile.relativeOutput}`;

if (!OUTPUT_ROOT.startsWith(`${SSD_MOUNT}/`)) {
  console.error(`Refusing to render outside the Portable SSD: ${OUTPUT_ROOT}`);
  process.exit(1);
}

if (!isMounted(SSD_MOUNT)) {
  console.error(`Portable SSD is not mounted at ${SSD_MOUNT}. Aborting so video is not written to internal storage.`);
  process.exit(1);
}

mkdirSync(outputPath.slice(0, outputPath.lastIndexOf("/")), { recursive: true });

const args = [
  "hyperframes",
  "render",
  "--quality",
  profile.quality,
  "--fps",
  "30",
  "--resolution",
  "portrait",
  "--output",
  outputPath,
  "--strict",
  ...extraArgs,
];

console.log(`Rendering ${kind} video to ${outputPath}`);

if (dryRun) {
  process.exit(0);
}

const child = spawn("npx", args, { stdio: "inherit" });
child.on("exit", (code, signal) => {
  if (signal) {
    console.error(`Render stopped by signal ${signal}`);
    process.exit(1);
  }
  process.exit(code ?? 1);
});

function getPacificDate() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function isMounted(path) {
  const result = spawnSync("mount", { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    return false;
  }
  return result.stdout.split("\n").some((line) => line.includes(` on ${path} (`));
}
