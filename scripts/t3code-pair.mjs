#!/usr/bin/env node
import { spawnSync } from "node:child_process";

const origin = process.argv[2] ?? "https://j2t3c.d.salehh.xyz";
const target = new URL(origin);
if (!["http:", "https:"].includes(target.protocol) || target.username || target.password || target.pathname !== "/" || target.search || target.hash) {
  throw new Error("Pass an HTTP(S) origin, without a path, credentials, query, or fragment.");
}
if (!process.env.T3CODE_BINARY || !process.env.T3CODE_HOME) {
  throw new Error("Run the Home Manager-installed t3code-pair command.");
}
const result = spawnSync(process.env.T3CODE_BINARY, ["pair", "--base-dir", process.env.T3CODE_HOME], { encoding: "utf8", env: process.env });
if (result.status !== 0) {
  process.stderr.write(result.stderr || "Could not mint a pairing link. Check t3code.service.\n");
  process.exit(result.status ?? 1);
}
// The CLI also prints a loopback QR code. Print only the remapped URL, so a
// remote client cannot accidentally scan an unusable loopback address.
const urls = result.stdout.match(/https?:\/\/[^\s\x1b]+/g) ?? [];
const link = urls.map((url) => {
  try { return new URL(url); } catch { return null; }
}).find((url) => url && (url.hash || url.search));
if (!link) throw new Error("The T3 CLI did not return a recognized pairing URL.");
link.protocol = target.protocol;
link.hostname = target.hostname;
link.port = target.port;
console.log(link.href);
