from __future__ import annotations

import ipaddress
import logging
import socket
import time
import urllib.robotparser
from dataclasses import dataclass, field
from datetime import date
from urllib.parse import urlparse

import requests

from .extraction import ExtractionError, extract_html, extract_pdf
from .models import ExtractedDocument, SourceConfig


LOG = logging.getLogger("nebula_rag.scraper")


@dataclass
class AcademicFetcher:
    user_agent: str = "NebulaAcademicResearchBot/0.1 (manual-review-required)"
    timeout_seconds: int = 20
    max_bytes: int = 10_000_000
    max_attempts: int = 2
    _last_request: dict[str, float] = field(default_factory=dict, init=False, repr=False)

    def _throttle(self, host: str, requests_per_minute: int) -> None:
        minimum_interval = 60.0 / max(1, requests_per_minute)
        elapsed = time.monotonic() - self._last_request.get(host, 0.0)
        if elapsed < minimum_interval:
            time.sleep(minimum_interval - elapsed)
        self._last_request[host] = time.monotonic()

    @staticmethod
    def _validate_network_target(url: str, source: SourceConfig) -> None:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        if parsed.scheme != "https" or parsed.username or parsed.password or host not in {
            item.lower() for item in source.allowed_hosts
        }:
            raise PermissionError("URL is outside the HTTPS source allowlist")
        if not any(parsed.path.startswith(prefix) for prefix in source.allowed_path_prefixes):
            raise PermissionError("URL path is outside the configured allowlist")
        try:
            addresses = {item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)}
        except socket.gaierror as exc:
            raise PermissionError("source host could not be resolved safely") from exc
        if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
            raise PermissionError("source host resolves to a non-public address")

    def fetch(self, url: str, source: SourceConfig) -> ExtractedDocument:
        if not source.enabled:
            raise PermissionError("source is disabled pending authorization review")
        parsed = urlparse(url)
        self._validate_network_target(url, source)
        host = parsed.hostname.lower()
        robots_url = f"https://{host}/robots.txt"
        robots = urllib.robotparser.RobotFileParser()
        try:
            self._throttle(host, source.requests_per_minute)
            robots_response = requests.get(robots_url, headers={"User-Agent": self.user_agent},
                                           timeout=self.timeout_seconds)
            robots_response.raise_for_status()
            if len(robots_response.content) > 1_000_000:
                raise PermissionError("robots.txt exceeds the safety size limit")
            robots.parse(robots_response.text.splitlines())
        except requests.RequestException as exc:
            raise PermissionError("robots.txt could not be verified") from exc
        if not robots.can_fetch(self.user_agent, url):
            raise PermissionError("robots.txt does not allow this fetch")
        last_error: Exception | None = None
        for attempt in range(self.max_attempts):
            try:
                self._throttle(host, source.requests_per_minute)
                response = requests.get(url, headers={"User-Agent": self.user_agent}, timeout=self.timeout_seconds,
                                        stream=True)
                response.raise_for_status()
                final_host = (urlparse(response.url).hostname or "").lower()
                if final_host not in {item.lower() for item in source.allowed_hosts}:
                    raise ExtractionError("redirect left the configured source allowlist")
                self._validate_network_target(response.url, source)
                declared_size = int(response.headers.get("Content-Length", "0") or 0)
                if declared_size > self.max_bytes:
                    raise ExtractionError("response exceeds configured size limit")
                parts, size = [], 0
                for part in response.iter_content(65536):
                    size += len(part)
                    if size > self.max_bytes:
                        raise ExtractionError("response exceeds configured size limit")
                    parts.append(part)
                body = b"".join(parts)
                content_type = response.headers.get("Content-Type", "").split(";", 1)[0].lower()
                if content_type in {"text/html", "application/xhtml+xml"}:
                    return extract_html(body, url=response.url, allowed_hosts=source.allowed_hosts,
                                        accessed_on=date.today(), source_type=source.source_type,
                                        classification={"information_type": source.information_type,
                                                        "authority_level": source.authority_level,
                                                        "curriculum_scope": source.curriculum_scope})
                if content_type == "application/pdf":
                    return extract_pdf(body, url=response.url, allowed_hosts=source.allowed_hosts,
                                       accessed_on=date.today(), source_type=source.source_type,
                                       classification={"information_type": source.information_type,
                                                       "authority_level": source.authority_level,
                                                       "curriculum_scope": source.curriculum_scope})
                raise ExtractionError("unsupported content type")
            except (requests.RequestException, ExtractionError) as exc:
                last_error = exc
                LOG.warning("fetch attempt failed", extra={"host": parsed.hostname, "attempt": attempt + 1})
                if attempt + 1 < self.max_attempts:
                    time.sleep(min(2 ** attempt, 2))
        raise ExtractionError("source fetch failed after limited retries") from last_error
