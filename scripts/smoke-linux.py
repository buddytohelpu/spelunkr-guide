#!/usr/bin/env python3
"""Exercise the real GTK/WebKit client on a Linux desktop (or under Xvfb)."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("spelunkr_linux", ROOT / "clients/linux/main.py")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
from gi.repository import GLib

OUTPUT = ROOT / "output/linux"
OUTPUT.mkdir(parents=True, exist_ok=True)
app = client.Application()
started = time.monotonic()
stage = "loading"
pending = False
exit_code = 1
observations = {}
last_progress = 0
script = """JSON.stringify({
  rows: document.querySelectorAll('.guide-row').length,
  errors: document.querySelectorAll('.row-error').length,
  selected: document.querySelector('.guide-row.selected')?.dataset.channel,
  tuned: document.getElementById('tuned-label')?.textContent,
  status: document.getElementById('schedule-status')?.textContent,
  message: document.getElementById('playback-message')?.textContent,
  watching: document.getElementById('television')?.classList.contains('watch-mode'),
  viewport: {width: innerWidth, height: innerHeight},
  videoRect: document.getElementById('video')?.getBoundingClientRect().toJSON(),
  creditsBottom: document.querySelector('.network-note')?.getBoundingClientRect().bottom,
  guideHeight: document.getElementById('guide-viewport')?.clientHeight,
  picture: document.documentElement.dataset.picture,
  objectFit: getComputedStyle(document.getElementById('video')).objectFit,
  help: document.getElementById('help-dialog')?.open,
  video: { ready: document.getElementById('video')?.readyState,
           paused: document.getElementById('video')?.paused,
           time: document.getElementById('video')?.currentTime,
           error: document.getElementById('video')?.error?.code },
  audioPaused: document.getElementById('station-audio')?.paused,
  hooks: !!window.spelunkr
})"""


def finish(ok, reason):
    global exit_code
    exit_code = 0 if ok else 1
    result = {"passed": ok, "reason": reason, "observations": observations}
    (OUTPUT / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    subprocess.run(["import", "-window", "root", str(OUTPUT / ("guide.png" if ok else "failed.png"))], check=False)
    app.quit()


def command(source):
    app.web.evaluate_javascript(source, -1, None, None, None, None, None)


def evaluated(web, result, _data):
    global pending, stage, last_progress
    pending = False
    try:
        value = web.evaluate_javascript_finish(result)
        state = json.loads(value.to_string())
    except Exception as error:
        finish(False, f"JavaScript evaluation failed: {error}")
        return
    if time.monotonic() - started > 120:
        observations["last"] = state
        finish(False, f"Timed out during {stage}")
        return
    if time.monotonic() - last_progress >= 15:
        print(json.dumps({"stage": stage, "state": state}), flush=True)
        last_progress = time.monotonic()
    if stage == "loading" and state.get("rows") == 31 and state.get("hooks"):
        observations["guide"] = state
        if state["errors"]:
            finish(False, "Guide contains channel errors")
            return
        if state["creditsBottom"] > state["viewport"]["height"] + 1 or state["guideHeight"] < 30:
            finish(False, "Guide does not fit the desktop window")
            return
        if state["video"]["ready"] < 2 or state["video"]["paused"]:
            return
        print("31 live channels and video playback ready", flush=True)
        command("window.spelunkr.action('down')")
        stage = "browse"
    elif stage == "browse":
        observations[stage] = state
        if state["selected"] == observations["guide"]["selected"] or state["tuned"] != observations["guide"]["tuned"]:
            finish(False, "Browsing did not preserve the playing channel")
            return
        command("window.spelunkr.action('ok')")
        stage = "watch"
    elif stage == "watch" and state["watching"] and state["video"]["ready"] >= 2 and not state["video"]["paused"]:
        observations[stage] = state
        if abs(state["videoRect"]["height"] - state["viewport"]["height"]) > 2 or abs(state["videoRect"]["width"] - state["viewport"]["width"]) > 2:
            finish(False, "Fullscreen video does not fill the window")
            return
        command("window.spelunkr.togglePicture()")
        stage = "picture"
    elif stage == "picture":
        observations[stage] = state
        expected = "original" if observations["watch"]["picture"] == "stretch" else "stretch"
        if state["picture"] != expected or state["objectFit"] != ("fill" if expected == "stretch" else "contain"):
            finish(False, "Picture mode did not change the video fitting")
            return
        command("window.spelunkr.togglePicture()")
        command("window.spelunkr.handleBack(); window.spelunkr.action('help')")
        stage = "help"
    elif stage == "help":
        observations[stage] = state
        if state["watching"] or not state["help"]:
            finish(False, "Guide/help navigation failed")
            return
        command("window.spelunkr.handleBack(); window.spelunkr.suspend()")
        stage = "suspend"
    elif stage == "suspend":
        observations[stage] = state
        if state["help"] or not state["video"]["paused"] or not state["audioPaused"]:
            finish(False, "Suspend failed to pause media")
            return
        command("window.spelunkr.resume()")
        stage = "resume"
    elif stage == "resume" and state["video"]["ready"] >= 2 and not state["video"]["paused"]:
        observations[stage] = state
        finish(True, "Live guide, visible fullscreen playback, picture fitting, navigation, help, suspend and resume passed")
        return


def poll():
    global pending
    if app.web and not pending:
        pending = True
        app.web.evaluate_javascript(script, -1, None, None, None, evaluated, None)
    return True


GLib.timeout_add(1000, poll)
app.run([sys.argv[0]])
raise SystemExit(exit_code)
