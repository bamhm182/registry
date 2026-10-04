#!/usr/bin/env python3
import json
import os
import pty
import pwd
import re
import signal
import socket
import subprocess
import threading
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = ${PORT}
INSTALL_DIR = os.path.expandvars("${INSTALL_DIR}")
MOSHI_HOOK = os.path.join(INSTALL_DIR, "moshi-hook")

LINK_RE = re.compile(r"^Link: (\S+)\s", re.MULTILINE)
LINK_TIMEOUT_SECONDS = 30
SETUP_MAX_SECONDS = 5 * 60

# The running `host setup` process and the link it printed, shared across
# requests so a reload doesn't spawn a duplicate.
state = threading.Condition()
setup_proc = None
setup_link = ""


def get_ip():
    # The address the kernel would use as the source for outbound traffic,
    # like `ip route get 1.1.1.1`. connect() on a UDP socket sends nothing.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]


def get_hostname():
    return socket.gethostname()


def get_username():
    return pwd.getpwuid(os.getuid()).pw_name


# This would be the preferred command as --json returns immediately, but it
# doesn't add the SSH key to the authorized_keys file
def get_deep_link_json():
    result = subprocess.run(
        [MOSHI_HOOK, "host", "setup", "--json"],
        capture_output=True, text=True, timeout=30, check=True
    )
    return json.loads(result.stdout)["deepLink"]


def start_setup():
    # Must be called with `state` held.
    global setup_proc, setup_link
    command = [
        MOSHI_HOOK, "host", "setup",
        "--host", get_ip(),
        "--name", get_hostname(),
        "--user", get_username(),
        "--force",
    ]
    # Run on a pty so the Link line is flushed as soon as it's printed, with
    # TERM=dumb so moshi-hook doesn't block querying the terminal.
    master, slave = pty.openpty()
    try:
        setup_proc = subprocess.Popen(
            command,
            stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True,
            env=dict(os.environ, TERM="dumb"),
        )
    except Exception:
        os.close(master)
        raise
    finally:
        os.close(slave)
    setup_link = ""
    threading.Thread(target=watch_setup, args=(setup_proc, master), daemon=True).start()


def kill_setup(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def watch_setup(proc, master):
    global setup_proc, setup_link
    # `host setup` keeps running after printing the link to finish pairing;
    # don't let it run forever if nobody completes it.
    timer = threading.Timer(SETUP_MAX_SECONDS, kill_setup, args=(proc,))
    timer.start()
    output = ""
    try:
        while True:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                # EIO once the child closes its end of the pty
                break
            if not chunk:
                break
            output += chunk.decode(errors="replace")
            links = LINK_RE.findall(output)
            if links:
                with state:
                    setup_link = links[-1]
                    state.notify_all()
    finally:
        timer.cancel()
        os.close(master)
        proc.wait()
        # Reset so the next request starts a fresh pairing
        with state:
            setup_proc = None
            setup_link = ""
            state.notify_all()


def get_deep_link_interactive():
    # Returns as soon as the Link line shows up; `host setup` is left
    # running in the background to see the pairing through.
    with state:
        if setup_proc is None:
            start_setup()
        state.wait_for(lambda: setup_link or setup_proc is None, LINK_TIMEOUT_SECONDS)
        if not setup_link:
            raise RuntimeError("no Link line from moshi-hook host setup")
        return setup_link


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] != "/":
            self.send_error(404)
            return

        try:
            link = get_deep_link_interactive()
        except (OSError, RuntimeError) as e:
            self.log_error("setup failed: %s", e)
            self.send_error(502, "moshi-hook setup failed")
            return

        # 302 redirect, plus an HTML fallback link in case the browser
        # won't auto-follow a custom URL scheme
        body = f'<a href="{escape(link, quote=True)}">Continue</a>'.encode()
        self.send_response(302)
        self.send_header("Location", link)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    print(f"Serving moshi-redirector on http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
