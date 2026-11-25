#!/usr/bin/env python3
"""Screen a pinned Git tree for the repository tampering seen in this incident."""

import argparse
import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import subprocess
import sys
from urllib.parse import urlsplit


KNOWN_BLOBS = {
    "b15ecc9810d9e346c1cb8cbdd9ee4dac40a32680": "History-rewrite batch file",
    "3982599c7b9c1f31e7314c04922b2ff1e34cc330": "Dana payload endpoint configuration",
    "502479ef85dbb2d5ac9997011e3cfa2af9b4a996": "Dana API client loader",
    "8a78a4f65637a8774912b02b8889adf450047faf": "Startup loader",
    "436169595f6080e03f8ead8ae581db3cf384d9dc": "Startup loader",
    "dcd30c6ebc4b1cc36d07e65ef2ed434e91adfb92": "Startup loader variant",
    "47aea8d70fe0c00f01a0dd8e502039824a6e2a86": "JavaScript disguised as a font",
}
SKIP_DIRECTORIES = {".git", "node_modules", ".next", ".venv", "site-packages", "__pycache__"}
FONT_EXTENSIONS = {".woff", ".woff2", ".ttf", ".otf", ".eot", ".orc", ".lkf"}
FONT_HEADERS = (b"wOFF", b"wOF2", b"OTTO", b"ttcf", b"\x00\x01\x00\x00")
STARTUP_NAMES = {"init", "api.js"}
MAX_FILE_BYTES = 700_000
BUILD_CONFIG = re.compile(
    r"^(?:postcss|tailwind|vite|astro|eslint|next|nuxt|babel|webpack|rollup|svelte|vitest|capacitor)"
    r"\.config\.[cm]?[jt]sx?$|^(?:\.eslintrc|\.postcssrc)\.[cm]?js$"
)
PADDED_CODE = re.compile(rb"(?m)[^ \r\n\t][ \t]{190,}([^ \r\n\t][^\r\n]{750,})")
HEX = re.compile(rb"\b0x[a-f0-9]{2,}\b", re.I)
STRING_TABLE = re.compile(rb"_\$_[0-9a-f]{3,12}|\b_0x[0-9a-f]{3,}\b", re.I)
UNICODE_BYTES = re.compile(rb"(?:\\u00[a-f0-9]{2}){32}", re.I)
JS_MARKER = re.compile(rb"\b(?:function\s*\(|require\s*\(|global(?:This)?\s*[\[.]|eval\s*\()")
FETCH_AND_EVAL = re.compile(rb"\batob\s*\(\s*process\.env\.AUTH_API_KEY\b")
ENCODED_ENDPOINT = re.compile(
    rb"""(?m)^[ \t]*(?:export[ \t]+)?AUTH_API_KEY[ \t]*=[ \t]*["']?([A-Za-z0-9+/_=-]{12,1024})"""
)
NODE_COMMAND = r"""(?:^|&&|\|\||[;|(\r\n])[ \t]*["']?node(?:\.exe)?["']?[ \t]+["']?"""
NODE_START = re.compile(
    NODE_COMMAND + r"((?:\.{1,2}/|[\w@.+-]+/)*(?:init|api\.js))(?=$|[\s;&|()\"'])", re.I
)
NODE_FONT = re.compile(
    NODE_COMMAND + r"([^\"';&|\r\n]+\.(?:woff2?|ttf|otf|eot|orc|lkf))(?=$|[\s;&|()\"'])", re.I
)
JSONC_COMMENTS = re.compile(r'("(?:[^"\\]|\\.)*")|//[^\r\n]*|/\*.*?\*/', re.S)
JSONC_TRAILING = re.compile(r'("(?:[^"\\]|\\.)*")|,(?=\s*[}\]])', re.S)


@dataclass(frozen=True)
class Finding:
    rule: str
    level: str
    path: str
    blob: str
    message: str
    fingerprint: str
    context: str = ""

    @property
    def identity(self):
        return self.rule, self.path, self.context, self.fingerprint

    def public(self):
        row = {"rule": self.rule, "level": self.level, "path": self.path,
               "blob": self.blob, "message": self.message}
        if self.context:
            row["context"] = self.context
        return row


class GitObjects:
    def __init__(self, directory):
        self.command = [
            "git", "-C", str(directory.resolve()), "-c", "core.hooksPath=/dev/null", "--no-optional-locks",
        ]
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "SSH_ASKPASS"))}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
                        GIT_CONFIG_NOSYSTEM="1", GIT_NO_REPLACE_OBJECTS="1",
                        GIT_TERMINAL_PROMPT="0", GIT_ALLOW_PROTOCOL="", GIT_NO_LAZY_FETCH="1")
        self.available_sizes = None

    def run(self, *args, payload=None):
        proc = subprocess.run(self.command + list(args), env=self.env, input=payload,
                              capture_output=True, timeout=60, check=False)
        if proc.returncode:
            raise ValueError(f"Git {args[0]} failed. Check that the repository and requested objects exist.")
        return proc.stdout

    def tree(self, ref):
        commit = self.run("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode().strip()
        entries = {}
        for record in self.run("ls-tree", "-r", "-z", commit).split(b"\0"):
            if record:
                meta, path = record.split(b"\t", 1)
                mode, kind, oid = meta.split()
                if kind == b"blob":
                    entries[os.fsdecode(path)] = mode.decode(), oid.decode()
        return commit, entries

    def blobs(self, ids):
        if not ids:
            return {}, set()
        # Enumerate objects already on disk so older Git never tries to hydrate
        # a missing object just to determine its size.
        if self.available_sizes is None:
            rows = self.run("cat-file", "--batch-all-objects", "--batch-check").splitlines()
            self.available_sizes = {
                oid.decode(): int(size) for oid, kind, size in (row.split() for row in rows)
                if kind == b"blob" and int(size) <= MAX_FILE_BYTES
            }
        cached = {}
        ordered = sorted(ids & self.available_sizes.keys())
        for offset in range(0, len(ordered), 64):
            batch = ordered[offset:offset + 64]
            query = ("\n".join(batch) + "\n").encode()
            raw = self.run("cat-file", "--batch", payload=query)
            start = 0
            for oid in batch:
                size = self.available_sizes[oid]
                end = raw.index(b"\n", start)
                if raw[start:end].split() != [oid.encode(), b"blob", str(size).encode()]:
                    raise ValueError("Git did not return the requested blob.")
                start = end + 1
                cached[oid] = raw[start:start + size]
                start += size + 1
        return cached, ids - cached.keys()


def candidate(path):
    parts = path.lower().split("/")
    name = parts[-1]
    if SKIP_DIRECTORIES.intersection(parts):
        return False
    return (
        name in STARTUP_NAMES | {"package.json", "config.bat", "api_client.ts", ".env"}
        or name.startswith((".env.", "temp_auto_push", "temp_interactive_push"))
        or bool(BUILD_CONFIG.fullmatch(name))
        or parts[-2:] == [".vscode", "tasks.json"]
        or posixpath.splitext(name)[1] in FONT_EXTENSIONS
    )


def digest(data):
    return hashlib.sha256(data).hexdigest()


def hidden_code(data):
    for match in PADDED_CODE.finditer(data):
        code = match[1]
        if len(HEX.findall(code)) >= 18 or len(STRING_TABLE.findall(code)) >= 10 or UNICODE_BYTES.search(code):
            return code
    return None


def encoded_endpoints(data):
    for match in ENCODED_ENDPOINT.finditer(data):
        value = match[1]
        try:
            decoded = base64.b64decode(value + b"=" * (-len(value) % 4), altchars=b"-_", validate=True)
            uri = urlsplit(decoded.decode("utf-8"))
            if uri.scheme in {"http", "https"} and uri.hostname:
                yield uri.hostname.lower().rstrip("."), digest(decoded)
        except (ValueError, UnicodeError):
            continue


def json_object(data, jsonc=False):
    try:
        text = data.decode("utf-8-sig")
        if jsonc:
            text = JSONC_COMMENTS.sub(lambda m: m[1] or "", text)
            text = JSONC_TRAILING.sub(lambda m: m[1] or "", text)
        obj = json.loads(text)
        return obj if isinstance(obj, dict) else {}
    except (UnicodeError, ValueError, RecursionError):
        return {}


def resolved_path(folder, value):
    workspace_root = "$" + "{workspaceFolder}/"
    value = value.strip()
    if value.startswith(workspace_root):
        value = value.removeprefix(workspace_root)
    path = posixpath.normpath(posixpath.join(folder, value))
    return path if path != ".." and not path.startswith(("../", "/")) else ""


def scan_file(path, oid, data):
    name = posixpath.basename(path).lower()
    extension = posixpath.splitext(name)[1]
    if name == ".env" or name.startswith(".env."):
        for host, fingerprint in encoded_endpoints(data):
            if host == "auth-confirm-eight.vercel.app":
                yield Finding("incident-endpoint", "block", path, oid, "Encoded endpoint matches the Dana incident.", fingerprint)
            else:
                yield Finding("encoded-endpoint", "review", path, oid, "AUTH_API_KEY encodes a URL. Review its use.", fingerprint)
        return
    if extension in FONT_EXTENSIONS:
        if not data.startswith(FONT_HEADERS) and JS_MARKER.search(data) and len(HEX.findall(data)) >= 25:
            yield Finding("disguised-font", "block", path, oid, "Font file contains obfuscated JavaScript.", digest(data))
        return
    hidden = hidden_code(data)
    if name in STARTUP_NAMES and (hidden or (JS_MARKER.search(data) and len(HEX.findall(data)) >= 100)):
        yield Finding("obfuscated-startup", "review", path, oid, "Review obfuscated code in this startup file.", digest(hidden or data))
    elif hidden:
        level = "block" if JS_MARKER.search(hidden) and (len(STRING_TABLE.findall(hidden)) >= 10 or UNICODE_BYTES.search(hidden)) else "review"
        yield Finding("padded-code", level, path, oid, "Obfuscated code follows horizontal padding.", digest(hidden))
    if FETCH_AND_EVAL.search(data) and re.search(rb"\bfetch\s*\(", data) and re.search(rb"\beval\s*\(", data):
        yield Finding("remote-evaluation", "block", path, oid, "Code evaluates a fetched response through the incident environment variable.", oid)
    if name.endswith(".bat") and re.search(rb"\bgit\s+commit\b[^\r\n]*--amend", data, re.I):
        if re.search(rb"\bgit\s+push\b[^\r\n]*(?:--force\b| -f\b)", data, re.I):
            yield Finding("history-rewrite-command", "review", path, oid, "Batch file amends commits and force-pushes. Review its purpose.", oid)


def invocation_findings(manifests, tasks, tree, payloads):
    for path, oid, scripts in manifests:
        for script, command in scripts.items():
            if not isinstance(command, str):
                continue
            for match in NODE_START.finditer(command):
                target = resolved_path(posixpath.dirname(path), match[1])
                if target in payloads:
                    yield Finding("npm-loader", "block", path, oid, "npm script invokes the matched loader.", payloads[target], f"{script} runs {target}")
    for path, oid, entries in tasks:
        folder = posixpath.dirname(posixpath.dirname(path))
        for task in entries:
            if not isinstance(task, dict) or not isinstance(task.get("runOptions"), dict) or task["runOptions"].get("runOn") != "folderOpen":
                continue
            command = task.get("command")
            args = task.get("args", [])
            if not isinstance(command, str) or not isinstance(args, list):
                continue
            line = " ".join([command, *(a for a in args if isinstance(a, str))])
            for match in NODE_START.finditer(line):
                target = resolved_path(folder, match[1])
                if target in payloads:
                    yield Finding("editor-loader", "block", path, oid, "Automatic editor task invokes the matched loader.", payloads[target], target)
            for match in NODE_FONT.finditer(line):
                target = resolved_path(folder, match[1])
                if target:
                    fingerprint = payloads.get(target, tree.get(target, ("", oid))[1])
                    level = "block" if target in payloads else "review"
                    yield Finding("editor-font-task", level, path, oid, "Automatic editor task runs a font path with Node.", fingerprint, target)


def scan(git, ref):
    commit, tree = git.tree(ref)
    interesting = [(path, mode, oid) for path, (mode, oid) in tree.items() if candidate(path)]
    blobs, unavailable = git.blobs({oid for _, mode, oid in interesting if mode != "120000" and oid not in KNOWN_BLOBS})
    incomplete = {path: oid for path, _, oid in interesting if oid in unavailable}
    findings, payloads, manifests, tasks = [], {}, [], []
    for path, (mode, oid) in tree.items():
        if oid in KNOWN_BLOBS and mode != "120000":
            findings.append(Finding("incident-blob", "block", path, oid, KNOWN_BLOBS[oid], oid))
            payloads[path] = oid
    for path, mode, oid in interesting:
        if mode == "120000":
            findings.append(Finding("symlink", "review", path, oid, "Review the symlink target for this execution path.", oid))
            continue
        data = blobs.get(oid)
        if data is None:
            continue
        name = posixpath.basename(path).lower()
        if name == "package.json":
            scripts = json_object(data).get("scripts", {})
            if isinstance(scripts, dict):
                manifests.append((path, oid, scripts))
        elif path.lower().endswith(".vscode/tasks.json"):
            entries = json_object(data, jsonc=True).get("tasks", [])
            if isinstance(entries, list):
                tasks.append((path, oid, entries))
        else:
            for finding in scan_file(path, oid, data):
                findings.append(finding)
                if finding.rule in {"obfuscated-startup", "disguised-font"}:
                    payloads[path] = finding.fingerprint
    findings.extend(invocation_findings(manifests, tasks, tree, payloads))
    findings = sorted(set(findings), key=lambda f: (f.path, f.rule, f.context, f.fingerprint))
    return commit, findings, incomplete


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path("."), help="Local checkout or bare Git repository")
    parser.add_argument("--ref", default="HEAD", help="Commit to inspect")
    parser.add_argument("--base", help="Trusted comparison commit. Only new blocking findings fail the check.")
    parser.add_argument("--json", action="store_true", help="Emit a machine-readable result without source contents")
    args = parser.parse_args(argv)
    try:
        git = GitObjects(args.repo)
        commit, findings, missing = scan(git, args.ref)
        base_sha = None
        prior = set()
        base_missing = {}
        if args.base:
            base_sha, previous, base_missing = scan(git, args.base)
            prior = {f.identity for f in previous}
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        message = f"Scan incomplete. {error}"
        print(json.dumps({"error": message}) if args.json else message, file=sys.stdout if args.json else sys.stderr)
        return 2
    results = [{**f.public(), "change": "preexisting" if f.identity in prior else "introduced" if base_sha else "present"}
               for f in findings]
    blockers = sum(row["level"] == "block" and row["change"] != "preexisting" for row in results)
    blocking_gaps = {path for path, oid in missing.items() if base_missing.get(path) != oid}
    if args.json:
        print(json.dumps({"commit": commit, "base": base_sha, "blocking_findings": blockers,
                          "findings": results, "uninspected_paths": sorted(missing),
                          "blocking_uninspected_paths": sorted(blocking_gaps)}, indent=2))
    else:
        print(f"Scanned {commit[:12]}. {blockers} blocking and {len(results) - blockers} other findings.")
        for row in results:
            location = repr(row["path"])
            if row.get("context"):
                location += f" ({row['context']!r})"
            print(f"{row['level'].upper()} {row['change']} {location} — {row['message']}")
        for path in sorted(missing):
            change = "blocking" if path in blocking_gaps else "preexisting"
            print(f"UNINSPECTED {change} {path!r} — Git object unavailable or exceeds {MAX_FILE_BYTES} bytes.")
    return 2 if blocking_gaps else 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
