#!/usr/bin/env python3
"""Open the one-time workflow setup PR before the publisher exists on dev."""

import argparse
import base64
import json
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


OWNER = "Ed-Davey"
REPOSITORY = "personal-radio-car-play"
HEAD = "setup/ed-codex-workflow"
ROOT = f"/repos/{OWNER}/{REPOSITORY}"


def api(path, token, body=None):
    request = Request(
        "https://api.github.com" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "User-Agent": "personal-radio-workflow-bootstrap",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        try:
            message = json.load(error).get("message", error.reason)
        except (ValueError, AttributeError):
            message = error.reason
        raise SystemExit(f"GitHub returned {error.code}: {message}") from None


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def app_jwt(client_id, private_key):
    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + 540, "iss": client_id}
    payload_segment = base64url(json.dumps(payload).encode())
    unsigned = base64url(b'{"alg":"RS256","typ":"JWT"}') + b"." + payload_segment
    signature = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(private_key)],
        input=unsigned,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    return (unsigned + b"." + base64url(signature)).decode("ascii")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--private-key", type=Path, required=True, help="Path to the downloaded PEM")
    parser.add_argument("--bot-login", default="ed-codex[bot]")
    args = parser.parse_args()
    key = args.private_key.expanduser().resolve()
    if not key.is_file():
        parser.error("The downloaded PEM file could not be found.")

    jwt = app_jwt(args.client_id, key)
    installation = api(f"{ROOT}/installation", jwt)
    token = api(
        f"/app/installations/{installation['id']}/access_tokens",
        jwt,
        {"repositories": [REPOSITORY], "permissions": {"pull_requests": "write"}},
    )["token"]

    query = urlencode({"state": "open", "head": f"{OWNER}:{HEAD}", "base": "dev"})
    existing = api(f"{ROOT}/pulls?{query}", token)
    pull = existing[0] if existing else api(
        f"{ROOT}/pulls",
        token,
        {
            "head": HEAD,
            "base": "dev",
            "title": "Set up Ed-Codex promotion reviews",
            "body": "Bootstrap the promotion publisher, Codex review gate and human review.",
            "draft": False,
        },
    )
    author = pull["user"]["login"]
    print(pull["html_url"])
    if author != args.bot_login:
        raise SystemExit(f"This PR was opened by {author}. The expected author is {args.bot_login}.")
    print(f"PR author: {author}")


if __name__ == "__main__":
    main()
