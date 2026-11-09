"""Checks tools/pixelfx_export.py's checkout guard (review Minor #6, 2026-11-09): the export stops unless the PixelFX
checkout is at COMMIT *and* clean (`git status --porcelain` empty: no edited, staged or untracked files), so every
sheet in assets/fx is what that commit renders. Run: python3 -I tools/test_pixelfx_export.py
Uses throwaway git repos in a temp dir (COMMIT is pointed at their HEAD); needs git and Pillow (the tool imports it)."""
import importlib.util, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def load_tool():
    spec = importlib.util.spec_from_file_location("pixelfx_export", os.path.join(HERE, "pixelfx_export.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def git(d, *args):
    return subprocess.run(["git", "-C", d, *args], check=True, capture_output=True, text=True).stdout.strip()

def make_repo(root):
    d = tempfile.mkdtemp(dir=root)
    git(d, "init", "-q")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")
    git(d, "config", "commit.gpgsign", "false")
    with open(os.path.join(d, "a.txt"), "w") as f: f.write("a\n")
    git(d, "add", "a.txt")
    git(d, "commit", "-q", "-m", "a")
    return d

def stops(tool, d):
    try:
        tool.check_commit(d)
    except SystemExit as e:
        return str(e.code)
    return ""

def main():
    tool = load_tool()
    fails = []
    with tempfile.TemporaryDirectory() as root:
        d = make_repo(root)
        tool.COMMIT = git(d, "rev-parse", "--short=7", "HEAD")
        if stops(tool, d): fails.append("clean checkout at COMMIT stopped: " + stops(tool, d))
        with open(os.path.join(d, "a.txt"), "w") as f: f.write("edited\n")
        msg = stops(tool, d)
        if not msg: fails.append("edited tracked file: export not stopped")
        elif "uncommitted" not in msg: fails.append("edited tracked file: message lacks 'uncommitted': " + msg)
        git(d, "checkout", "-q", "--", "a.txt")
        with open(os.path.join(d, "new.mjs"), "w") as f: f.write("x\n")
        if not stops(tool, d): fails.append("untracked file: export not stopped")
        os.remove(os.path.join(d, "new.mjs"))
        with open(os.path.join(d, "a.txt"), "w") as f: f.write("staged\n")
        git(d, "add", "a.txt")
        if not stops(tool, d): fails.append("staged change: export not stopped")
        git(d, "reset", "-q", "--hard")
        if stops(tool, d): fails.append("clean again: stopped: " + stops(tool, d))
        tool.COMMIT = "0000000"
        if not stops(tool, d): fails.append("wrong commit: export not stopped")
    print("\n".join(fails) if fails else "PASS pixelfx_export checkout guard (6 cases)")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
