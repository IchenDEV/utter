#!/usr/bin/env python3
"""Report public Hub metadata headers without credentials or signed redirect URLs."""

import json
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def probe(origin, repository):
    url = f"{origin}/{repository}/resolve/main/README.md"
    result = {"origin": origin, "repository": repository, "responses": []}
    opener = build_opener(ProxyHandler({}), NoRedirect())
    for _ in range(4):
        try:
            try:
                response = opener.open(Request(url, method="HEAD"), timeout=15)
            except HTTPError as error:
                response = error
            with response:
                location = response.headers.get("Location")
                redirected = urljoin(url, location) if location else None
                result["responses"].append({
                    "host": urlsplit(url).hostname,
                    "status": response.code,
                    "etag": bool(response.headers.get("ETag") or response.headers.get("X-Linked-Etag")),
                    "repo_commit": bool(response.headers.get("X-Repo-Commit")),
                    "redirect_host": urlsplit(redirected).hostname if redirected else None,
                })
                if redirected and urlsplit(redirected).hostname == urlsplit(url).hostname:
                    url = redirected
                    continue
                return result
        except (URLError, TimeoutError) as error:
            result["error"] = type(error).__name__
            return result
    result["error"] = "relative redirect limit"
    return result


if __name__ == "__main__":
    for repository in ("argmaxinc/whisperkit-coreml", "mlx-community/Qwen2.5-0.5B-Instruct-4bit"):
        for origin in ("https://huggingface.co", "https://hf-mirror.com"):
            print(json.dumps(probe(origin, repository)), flush=True)
