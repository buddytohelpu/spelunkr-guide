#!/usr/bin/env python3
"""Self-contained GTK/WebKit desktop client for the bundled direct broadcast guide."""
import functools
import http.server
import json
import os
from pathlib import Path
import sys
import threading
from urllib.parse import urlparse

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("WebKit", "6.0")
from gi.repository import Gdk, Gio, Gtk, WebKit

APP_ID = "io.github.buddy.SpelunkrGuide"
ASSETS = Path(__file__).resolve().parent / "web"
if not ASSETS.is_dir():
    ASSETS = Path(__file__).resolve().parents[2] / "web"


class AssetHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *_args):
        pass


class Application(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.window = None
        self.web = None
        self.server = None

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        # The loopback server is part of this process and serves bundled files only.
        # Broadcast data and media requests go directly from WebKit to public HTTPS feeds.
        data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / APP_ID
        cache = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / APP_ID
        data.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        settings_file = data / "client.json"
        port = 0
        try:
            saved_port = json.loads(settings_file.read_text()).get("assetPort", 0)
            if isinstance(saved_port, int) and 1024 <= saved_port <= 65535:
                port = saved_port
        except (OSError, ValueError, TypeError, AttributeError):
            pass
        handler = functools.partial(AssetHandler, directory=str(ASSETS))
        try:
            self.server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
        except OSError:
            self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        settings_file.write_text(json.dumps({"assetPort": self.server.server_port}) + "\n")
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.window = Gtk.ApplicationWindow(application=self, title="Spelunkr Guide")
        width, height = 1280, 800
        display = Gdk.Display.get_default()
        if display and display.get_monitors().get_n_items():
            bounds = display.get_monitors().get_item(0).get_geometry()
            width = min(width, max(320, bounds.width - 64))
            height = min(height, max(240, bounds.height - 64))
        self.window.set_default_size(width, height)
        self.window.set_size_request(480, 320)
        session = WebKit.NetworkSession.new(str(data), str(cache))
        self.web = WebKit.WebView(
            network_session=session,
            website_policies=WebKit.WebsitePolicies(autoplay=WebKit.AutoplayPolicy.ALLOW),
        )
        self.web.get_settings().set_media_playback_requires_user_gesture(False)
        self.web.connect("decide-policy", self.on_policy)
        self.web.connect("create", self.on_new_window)
        self.window.set_child(self.web)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        self.window.add_controller(keys)
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.quit())
        self.add_action(quit_action)
        self.set_accels_for_action("app.quit", ["<Primary>q"])
        self.web.load_uri(self.origin + "/index.html?native=linux")
        self.window.present()

    def on_policy(self, _web, decision, kind):
        if kind in (WebKit.PolicyDecisionType.NAVIGATION_ACTION, WebKit.PolicyDecisionType.NEW_WINDOW_ACTION):
            uri = decision.get_navigation_action().get_request().get_uri()
            if uri.startswith(self.origin + "/"):
                return False
            decision.ignore()
            if urlparse(uri).scheme == "https":
                Gtk.show_uri(self.window, uri, Gdk.CURRENT_TIME)
            return True
        return False

    def on_new_window(self, _web, action):
        uri = action.get_request().get_uri()
        if urlparse(uri).scheme == "https":
            Gtk.show_uri(self.window, uri, Gdk.CURRENT_TIME)
        return None

    def on_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_F11:
            if self.window.is_fullscreen():
                self.window.unfullscreen()
            else:
                self.window.fullscreen()
            return True
        return False

    def do_shutdown(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        Gtk.Application.do_shutdown(self)


if __name__ == "__main__":
    raise SystemExit(Application().run(sys.argv))
