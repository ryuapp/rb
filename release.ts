import { crypto } from "@std/crypto";
import { encodeHex } from "@std/encoding/hex";
import zonToJson from "z2j";

function loadBuildZigZon() {
  const zon = zonToJson(Deno.readTextFileSync("build.zig.zon"));
  return JSON.parse(zon);
}

const zip = new Deno.Command("powershell", {
  args: [
    "Compress-Archive -Path zig-out/bin/rb.exe -DestinationPath dist/rb-x86_64-pc-windows-msvc.zip -Force",
  ],
});

zip.spawn();
const buildZigZon = loadBuildZigZon();
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

Deno.writeFileSync(
  "rb.json",
  new TextEncoder().encode(JSON.stringify(scoopTemplate, null, 2) + "\n"),
);
