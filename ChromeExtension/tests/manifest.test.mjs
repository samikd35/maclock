import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manifest = JSON.parse(
  await readFile(new URL("../manifest.json", import.meta.url), "utf8"),
);

test("is a local-only Manifest V3 extension with the fixed identity", () => {
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.background.service_worker, "service-worker.js");
  assert.equal(manifest.background.type, "module");
  assert.equal(manifest.incognito, "not_allowed");
  assert.equal(manifest.version, "0.3.0");
  assert.deepEqual(
    [...manifest.permissions].sort(),
    ["favicon", "nativeMessaging", "storage", "tabs", "webNavigation"],
  );
  assert.equal(manifest.host_permissions, undefined);

  const digest = createHash("sha256")
    .update(Buffer.from(manifest.key, "base64"))
    .digest()
    .subarray(0, 16);
  const extensionId = [...digest]
    .flatMap((byte) => [byte >> 4, byte & 15])
    .map((nibble) => String.fromCharCode(97 + nibble))
    .join("");
  assert.equal(extensionId, "hoofhoedlagpoclhkgnkmejaihaapoke");
});
