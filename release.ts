import $ from "@david/dax";
import { crypto } from "@std/crypto";
import { encodeHex } from "@std/encoding/hex";
import { ZON } from "zzon";

// Check versions
const buildZigZon = ZON.parse(Deno.readTextFileSync("build.zig.zon"));
const versionMsgs = await $`zig-out/bin/rb.exe --version`.stdout("piped")
  .stderr("piped");
const version = versionMsgs.stderr.trim().split(" ").at(1);
if (version !== buildZigZon.version) {
  throw new Error(
    `Version mismatch: build.zig.zon is ${buildZigZon.version}, but CLI is ${version}`,
  );
}

// create dist directory
await Deno.mkdir("dist", { recursive: true });
// zip the binary
await $`powershell Compress-Archive -Path zig-out/bin/rb.exe -DestinationPath dist/rb-x86_64-pc-windows-msvc.zip -Force`;

const data = await Deno.readFile("dist/rb-x86_64-pc-windows-msvc.zip");
const hash = encodeHex(await crypto.subtle.digest("SHA-256", data));

const scoopTemplate = {
  version: buildZigZon.version,
  homepage: "https://github.com/ryuapp/rb",
  license: "MIT",
  architecture: {
    "64bit": {
      url:
        `https://github.com/ryuapp/rb/releases/download/v${buildZigZon.version}/rb-x86_64-pc-windows-msvc.zip`,
      hash: hash,
    },
  },
  bin: "rb.exe",
  checkver: "github",
  autoupdate: {
    architecture: {
      "64bit": {
        url:
          "https://github.com/ryuapp/rb/releases/download/v$version/rb-x86_64-pc-windows-msvc.zip",
      },
    },
  },
};

// update scoop config
Deno.writeFileSync(
  "rb.json",
  new TextEncoder().encode(JSON.stringify(scoopTemplate, null, 2) + "\n"),
);
