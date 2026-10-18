#!/usr/bin/env python3
"""check-invisibility.py - the static half of the CRU "invisibility test".

Operator standard (2026-10-17): *installed software shows tray icons and desktop icons only - never a console window
(cmd, PowerShell, Windows Terminal) at startup, at logon, on a schedule or in normal background work.* On Windows 11
the default console host is Windows Terminal, and `powershell.exe -WindowStyle Hidden` hides a window only AFTER it
exists (Windows Terminal ignores the hide), so the usual "hidden" launch is not invisible. Authority and examples:
hub guides/invisibility/README.md.

What this checker does: it reads the code that LAUNCHES programs on Windows and fails on the launch shapes that
create a console window. It cannot see what really happens on a machine; the runtime half is
Watch-NoConsoleWindows.ps1 in the same folder.

Rules (each finding names its rule):
  INV-GO-EXEC        Go: exec.Command/CommandContext in Windows code with no CREATE_NO_WINDOW (or a repo's own hide
                     helper, see "markers") on the same command within the next lines.
  INV-GO-HIDEONLY    Go: a SysProcAttr{...HideWindow...} literal without CREATE_NO_WINDOW (hides a console that exists).
  INV-PS-TASK        PowerShell: New-ScheduledTaskAction runs powershell/pwsh/cmd/a .bat/.cmd/conhost (without
                     --headless) and the file never makes the task run as SYSTEM/S4U/stored password: it runs in the
                     user's session and shows a window.
  INV-SCHTASKS       any file: `schtasks /create ... /tr <console program>` without `/ru SYSTEM`.
  INV-TASK-XML       task XML: <LogonType>InteractiveToken</LogonType> with a console <Command>.
  INV-RUNKEY         any file: a ...\\CurrentVersion\\Run(Once) value that starts a console program without
                     `conhost.exe --headless`.
  INV-PS-STARTPROC   PowerShell: Start-Process of powershell/pwsh/cmd without -WindowStyle Hidden.
  INV-CS-PROCESS     C#: ProcessStartInfo / Process.Start of powershell/cmd without CreateNoWindow = true.
  INV-NSIS-EXEC      NSIS: Exec/ExecWait of a console program (use nsExec::Exec / nsExec::ExecToLog).
  INV-INNO-RUN       Inno Setup: a [Run] entry for a console program without the runhidden flag.
RISK (reported, never failing): a hidden Start-Process of PowerShell in a user session - whether Windows
Terminal honours -WindowStyle Hidden depends on the Windows build (this doc line describes the shape; invisibility:allow doc-example).

Waiver: put `invisibility:allow <reason>` in a comment on the finding's line or the line above. A reason is required.
Baseline (adopting in a repo that already has findings): `--write-baseline` records today's findings in
ci/invisibility-baseline.json; afterwards only NEW findings fail (matched by rule + file + line text, not line number,
so moving code does not break the gate). Shrink the baseline as findings are fixed; growing it is a reviewed decision.
Repo config (optional) ci/invisibility.json: {"exclude": ["glob", ...], "markers": ["myHideHelper(", ...]}.

    python3 ci/check-invisibility.py [--root DIR] [--json OUT] [--write-baseline] [--all]
Exit: 0 = no new failing finding; 1 = new failing findings; 2 = usage/config error. --all prints baselined findings too.
"""
import argparse
import fnmatch
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

CONSOLE = r"(?:powershell(?:\.exe)?|pwsh(?:\.exe)?|cmd(?:\.exe)?|cscript(?:\.exe)?|[\w.$%{}\\/-]+\.(?:bat|cmd))\b"
CONSOLE_RE = re.compile(CONSOLE, re.I)
NOWINDOW_MARKERS = ("CREATE_NO_WINDOW", "createNoWindow", "0x08000000", "0x8000000", "hideConsoleWindow(",
                    "HideConsoleWindow(", "CreateNoWindow", "DETACHED_PROCESS", "detachedProcess")
GO_LOOKAHEAD = 14
DEFAULT_EXCLUDE = ("vendor/*", "*/vendor/*", "node_modules/*", "*/node_modules/*", ".git/*", "*_test.go", "*/testdata/*",
                   "*/fixtures/*", "test_*.py", "*/test_*.py", "test-*.py", "*/test-*.py", "*.Tests.ps1",
                   "*/tests/*", "tests/*", "*.retired",
                   "archive/*", "*/archive/*", "docs/*", "*.md")
WAIVER = re.compile(r"invisibility:allow\s+\S", re.I)


def tracked_files(root):
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                             capture_output=True, check=True).stdout
        names = [n for n in out.decode("utf-8", "replace").split("\0") if n]
        if names:
            return names
    except (OSError, subprocess.CalledProcessError):
        pass
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "vendor")]
        for f in files:
            found.append(os.path.relpath(os.path.join(base, f), root).replace(os.sep, "/"))
    return found


def excluded(rel, patterns):
    return any(fnmatch.fnmatch(rel, p) for p in patterns)


def waived(lines, i):
    return bool(WAIVER.search(lines[i]) or (i > 0 and WAIVER.search(lines[i - 1])))


class Scan:
    def __init__(self, markers):
        self.findings = []
        self.markers = tuple(NOWINDOW_MARKERS) + tuple(markers)

    def add(self, rule, rel, lines, i, why, severity="FAIL"):
        if waived(lines, i):
            return
        text = lines[i].strip()
        self.findings.append({"rule": rule, "severity": severity, "path": rel, "line": i + 1, "text": text[:200],
                              "why": why, "fingerprint": hashlib.sha256(" ".join(text.split()).encode()).hexdigest()[:16]})

    # --- Go ------------------------------------------------------------------------------------------------------
    def go(self, rel, text, lines):
        windows = rel.endswith("_windows.go") or "//go:build windows" in text[:400] or "+build windows" in text[:400]
        if not windows:
            return
        for i, line in enumerate(lines):
            code = line.split("//", 1)[0]
            if re.search(r"\bexec\.Command(Context)?\(", code):
                window = "\n".join(lines[i:i + GO_LOOKAHEAD])
                if not any(m in window for m in self.markers):
                    self.add("INV-GO-EXEC", rel, lines, i, "child process started without CREATE_NO_WINDOW: a console "
                             "program gets a NEW console window when the parent has none (tray, GUI build, service)")
            for lit in re.finditer(r"SysProcAttr\{[^}]*\}", code):
                if "HideWindow" in lit.group(0) and not any(m in lit.group(0) for m in self.markers):
                    self.add("INV-GO-HIDEONLY", rel, lines, i, "HideWindow only hides a console that already exists "
                             "(and Windows Terminal may ignore it); add CREATE_NO_WINDOW")

    # --- PowerShell ------------------------------------------------------------------------------------------------
    # A task runs outside the user's session only when its OWN registration says so: a principal or Register-* call
    # near the action (not any word "password" elsewhere in the file - that once excused a real user-session task).
    SYSTEM_PRINCIPAL = re.compile(
        r"New-ScheduledTaskPrincipal\b[^\n]*(?:-UserId\s+['\"]?(?:SYSTEM|NT AUTHORITY\\SYSTEM|S-1-5-18)\b|"
        r"-LogonType\s+['\"]?(?:S4U|Password|ServiceAccount)\b)", re.I)
    # Register-ScheduledTask -User <account> -Password <secret> (a stored-password task) or -User SYSTEM; the
    # arguments are often on the next line (string concatenation in Python/Go/TypeScript)
    REGISTER_OFF_SESSION = re.compile(r"-Password\s+['\"$]?\S|-User\s+['\"]?(?:SYSTEM|NT AUTHORITY\\SYSTEM|S-1-5-18)\b", re.I)
    PRINCIPAL_WINDOW = 30

    def off_session(self, lines, i):
        nearby = "\n".join(lines[max(0, i - self.PRINCIPAL_WINDOW):i + self.PRINCIPAL_WINDOW + 1])
        if self.SYSTEM_PRINCIPAL.search(nearby):
            return True
        for j in range(max(0, i - self.PRINCIPAL_WINDOW), min(len(lines), i + self.PRINCIPAL_WINDOW + 1)):
            if re.search(r"Register-ScheduledTask\b", lines[j], re.I) and \
                    self.REGISTER_OFF_SESSION.search("\n".join(lines[j:j + 3])):
                return True
        return False

    def powershell(self, rel, text, lines):
        for i, line in enumerate(lines):
            code = line.split("#", 1)[0] if not line.lstrip().startswith("<#") else ""
            if re.search(r"New-ScheduledTaskAction\b", code, re.I):
                system_task = self.off_session(lines, i)
                window = " ".join(lines[i:i + 4])
                exe = re.search(r"-Execute\s+(['\"]?)([^'\"\s`]+)\1", window, re.I)
                target = exe.group(2) if exe else ""
                # the argument string (often holding --headless) is frequently built into a variable just
                # above the New-ScheduledTaskAction line, so look a few lines back for the windowless marker
                headwin = " ".join(lines[max(0, i - 5):i + 4])
                headless = "--headless" in headwin or re.search(r"pythonw|hidden_run|wscript", headwin, re.I)
                if exe and CONSOLE_RE.search(target + " ") or re.search(r"conhost", target, re.I):
                    if not headless and not system_task:
                        self.add("INV-PS-TASK", rel, lines, i, "scheduled task runs a console program in the user's "
                                 "session (no SYSTEM/S4U principal in this file): its window shows for the whole run")
            if re.search(r"\bStart-Process\b", code, re.I):
                window = " ".join(lines[i:i + 3])
                fp = re.search(r"Start-Process\s+(?:-FilePath\s+)?(['\"]?)([^'\"\s`]+)\1", window, re.I)
                target = fp.group(2) if fp else ""
                if re.fullmatch(r"(?:.*[\\/])?(?:powershell|pwsh|cmd)(?:\.exe)?", target, re.I) or target.lower().endswith((".bat", ".cmd")):
                    if re.search(r"-WindowStyle\s+['\"]?Hidden", window, re.I):
                        self.add("INV-PS-STARTPROC", rel, lines, i, "created hidden: whether Windows Terminal honours "
                                 "it depends on the build; prefer a windowless launcher", severity="RISK")
                    elif not re.search(r"-NoNewWindow", window, re.I):
                        self.add("INV-PS-STARTPROC", rel, lines, i, "starts a console program in a new visible window")

    # --- rules for every text file ----------------------------------------------------------------------------------
    def common(self, rel, text, lines):
        for i, line in enumerate(lines):
            if re.search(r"schtasks(?:\.exe)?['\"]?\s*[,\s]\s*['\"]?/create", line, re.I) or (
                    re.search(r"schtasks", line, re.I) and re.search(r"['\"]/create['\"]", line, re.I)):
                window = " ".join(lines[i:i + 8])
                tr = re.search(r"/tr\b(.{0,200})", window, re.I)
                if tr and CONSOLE_RE.search(tr.group(1)) and "--headless" not in tr.group(1) \
                        and not re.search(r"/ru\s*['\"]?\s*(?:,\s*)?['\"]?(?:SYSTEM|NT AUTHORITY\\+SYSTEM|S-1-5-18)", window, re.I):
                    self.add("INV-SCHTASKS", rel, lines, i, "schtasks task runs a console program and is not /ru SYSTEM: "
                             "it runs in a user session with a visible window")
                elif tr and re.search(r"/sc\s+onlogon", window, re.I) and not re.search(
                        r"/ru\s*['\"]?\s*(?:,\s*)?['\"]?(?:SYSTEM|NT AUTHORITY\\+SYSTEM|S-1-5-18)", window, re.I):
                    self.add("INV-SCHTASKS", rel, lines, i, "logon task in the user session whose target this checker cannot "
                             "read: confirm it is not a console program", severity="RISK")
            if re.search(r"CurrentVersion\\+Run(?:Once)?\b", line, re.I):
                window = " ".join(lines[max(0, i - 2):i + 8])
                writes = re.search(r"New-ItemProperty|Set-ItemProperty|reg(?:\.exe)?\s+add|SetStringValue|SetValue|WriteRegStr|"
                                   r"WriteRegExpandStr|Registry\.SetValue", window, re.I)
                if writes and CONSOLE_RE.search(window) and "--headless" not in window:
                    self.add("INV-RUNKEY", rel, lines, i, "a Run/RunOnce value that starts a console program flashes "
                             "(or keeps) a window at every logon; use conhost.exe --headless or a GUI launcher")

    def task_xml(self, rel, text, lines):
        if "InteractiveToken" not in text:
            return
        for i, line in enumerate(lines):
            m = re.search(r"<Command>(.*?)</Command>", line, re.I)
            if m and CONSOLE_RE.search(m.group(1) + " ") and "--headless" not in text:
                self.add("INV-TASK-XML", rel, lines, i, "interactive-token task runs a console program")

    def csharp(self, rel, text, lines):
        for i, line in enumerate(lines):
            if re.search(r"new\s+ProcessStartInfo\b|Process\.Start\(", line) and CONSOLE_RE.search(" ".join(lines[i:i + 3])):
                window = "\n".join(lines[i:i + 12])
                if not re.search(r"CreateNoWindow\s*=\s*true", window):
                    self.add("INV-CS-PROCESS", rel, lines, i, "process start without CreateNoWindow = true")

    def nsis(self, rel, text, lines):
        for i, line in enumerate(lines):
            code = line.split(";", 1)[0]
            if re.match(r"\s*(?:Exec|ExecWait)\s", code, re.I) and CONSOLE_RE.search(code):
                self.add("INV-NSIS-EXEC", rel, lines, i, "Exec/ExecWait shows the console; use nsExec::Exec")

    def inno(self, rel, text, lines):
        section = ""
        for i, line in enumerate(lines):
            s = line.strip()
            if s.startswith("[") and s.endswith("]"):
                section = s.lower()
                continue
            if section == "[run]" and re.search(r"Filename:\s*\"?[^;]*" + CONSOLE, s, re.I) and "runhidden" not in s.lower():
                self.add("INV-INNO-RUN", rel, lines, i, "[Run] entry for a console program without runhidden")


def scan(root, config):
    s = Scan(config.get("markers", []))
    patterns = DEFAULT_EXCLUDE + tuple(config.get("exclude", []))
    for rel in tracked_files(root):
        if excluded(rel, patterns):
            continue
        low = rel.lower()
        if not low.endswith((".go", ".ps1", ".psm1", ".cs", ".nsi", ".nsh", ".iss", ".xml", ".bat", ".cmd", ".py", ".sh",
                             ".ts", ".js", ".cjs", ".mjs", ".json")):
            continue
        path = pathlib.Path(root) / rel
        try:
            if path.stat().st_size > 2_000_000:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        lines = text.splitlines()
        if low.endswith(".go"):
            s.go(rel, text, lines)
        if low.endswith((".ps1", ".psm1", ".go", ".py", ".ts", ".js", ".cjs", ".mjs", ".sh", ".cs")):
            # PowerShell is also embedded in Go, Python, TypeScript and shell strings across the estate
            s.powershell(rel, text, lines)
        if low.endswith(".cs"):
            s.csharp(rel, text, lines)
        elif low.endswith((".nsi", ".nsh")):
            s.nsis(rel, text, lines)
        elif low.endswith(".iss"):
            s.inno(rel, text, lines)
        elif low.endswith(".xml"):
            s.task_xml(rel, text, lines)
        if not low.endswith(".json"):
            s.common(rel, text, lines)
    return s.findings


def key(f):
    return (f["rule"], f["path"], f["fingerprint"])


def main(argv=None):
    ap = argparse.ArgumentParser(description="CRU invisibility test: launch shapes that show a console window")
    ap.add_argument("--root", default=".")
    ap.add_argument("--json", help="write every finding (with baseline status) to this file")
    ap.add_argument("--write-baseline", action="store_true", help="record today's failing findings as the baseline")
    ap.add_argument("--all", action="store_true", help="also print baselined findings and RISK items")
    a = ap.parse_args(argv)
    root = pathlib.Path(a.root).resolve()
    cfg_path, base_path = root / "ci" / "invisibility.json", root / "ci" / "invisibility-baseline.json"
    try:
        config = json.loads(cfg_path.read_text(encoding="utf-8")) if cfg_path.exists() else {}
        baseline = json.loads(base_path.read_text(encoding="utf-8")) if base_path.exists() else {"findings": []}
    except (OSError, ValueError) as e:
        print(f"invisibility: unreadable config or baseline: {e}", file=sys.stderr)
        return 2
    findings = scan(root, config)
    failing = [f for f in findings if f["severity"] == "FAIL"]
    if a.write_baseline:
        counts = {}
        for f in failing:
            counts[key(f)] = counts.get(key(f), 0) + 1
        out = {"version": 1, "note": "Findings accepted when the invisibility gate was adopted; fix and remove, never add "
               "without review (hub guides/invisibility/README.md).",
               "findings": [{"rule": k[0], "path": k[1], "fingerprint": k[2], "count": n,
                             "example": next(f["text"] for f in failing if key(f) == k)} for k, n in sorted(counts.items())]}
        base_path.parent.mkdir(parents=True, exist_ok=True)
        base_path.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
        print(f"invisibility: baseline written with {len(failing)} finding(s) in {len(counts)} group(s): {base_path}")
        return 0
    allowed = {(b["rule"], b["path"], b["fingerprint"]): int(b.get("count", 1)) for b in baseline.get("findings", [])}
    used, new = {}, []
    for f in failing:
        k = key(f)
        used[k] = used.get(k, 0) + 1
        f["baselined"] = used[k] <= allowed.get(k, 0)
        if not f["baselined"]:
            new.append(f)
    fixed = sum(max(0, n - used.get(k, 0)) for k, n in allowed.items())
    risks = [f for f in findings if f["severity"] == "RISK"]
    show = findings if a.all else new
    for f in show:
        tag = "RISK" if f["severity"] == "RISK" else ("baselined" if f.get("baselined") else "NEW FAIL")
        print(f"{tag:9s} {f['rule']:16s} {f['path']}:{f['line']}  {f['text'][:110]}\n          -> {f['why']}")
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps({"root": str(root), "findings": findings, "new_failing": len(new),
                                                    "baselined": len(failing) - len(new), "risk": len(risks),
                                                    "baseline_entries_now_fixed": fixed}, indent=1), encoding="utf-8")
    verdict = "FAIL" if new else "PASS"
    print(f"invisibility {verdict}: {len(new)} new failing finding(s), {len(failing) - len(new)} baselined, "
          f"{len(risks)} RISK; {fixed} baselined finding(s) no longer present (shrink the baseline)")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
