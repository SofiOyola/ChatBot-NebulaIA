from __future__ import annotations

import hashlib
import io
import re
from datetime import date
from html.parser import HTMLParser
from urllib.parse import urlparse

from .models import ExtractedDocument


class ExtractionError(ValueError):
    pass


class _AcademicHTMLParser(HTMLParser):
    SKIP = {"script", "style", "nav", "header", "footer", "aside", "form", "noscript"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.in_title = False
        self.title: list[str] = []
        self.parts: list[str] = []
        self.published_candidates: list[str] = []
        self.heading_tag: str | None = None
        self.heading_parts: list[str] = []
        self.headings: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        tag = tag.lower()
        attributes = {str(key).lower(): value for key, value in attrs if value is not None}
        if tag == "meta" and attributes.get("property", "").lower() in {
            "article:published_time", "datepublished"
        } and attributes.get("content"):
            self.published_candidates.append(attributes["content"])
        if tag == "time" and attributes.get("datetime"):
            self.published_candidates.append(attributes["datetime"])
        if tag in {"h1", "h2", "h3", "h4"}:
            self.heading_tag, self.heading_parts = tag, []
        if tag in self.SKIP:
            self.skip_depth += 1
        if tag == "title":
            self.in_title = True
        if not self.skip_depth and tag in {"p", "li", "h1", "h2", "h3", "h4", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag == "title":
            self.in_title = False
        if tag in self.SKIP and self.skip_depth:
            self.skip_depth -= 1
        if not self.skip_depth and tag in {"p", "li", "h1", "h2", "h3", "h4"}:
            self.parts.append("\n")
        if tag == self.heading_tag:
            heading = _clean(" ".join(self.heading_parts))
            if heading:
                self.headings.append(heading)
            self.heading_tag, self.heading_parts = None, []

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title.append(data)
        if not self.skip_depth and not self.in_title:
            self.parts.append(data)
            if self.heading_tag:
                self.heading_parts.append(data)


def _clean(text: str) -> str:
    lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def _validate_public_https(url: str, allowed_hosts: tuple[str, ...]) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ExtractionError("source URL must be public HTTPS without credentials")
    host = parsed.hostname.lower()
    if host not in {item.lower() for item in allowed_hosts}:
        raise ExtractionError("source host is not allowlisted")


def _declared_date(values: list[str]) -> date | None:
    for value in values:
        try:
            return date.fromisoformat(value.strip()[:10])
        except ValueError:
            continue
    return None


def extract_html(data: bytes, *, url: str, allowed_hosts: tuple[str, ...], accessed_on: date,
                 source_type: str = "official", classification: dict | None = None) -> ExtractedDocument:
    _validate_public_https(url, allowed_hosts)
    parser = _AcademicHTMLParser()
    try:
        parser.feed(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ExtractionError("invalid UTF-8 HTML") from exc
    content = _clean("".join(parser.parts))
    title = _clean(" ".join(parser.title))
    if not title or not content:
        raise ExtractionError("HTML has no usable title or content")
    return ExtractedDocument(title, url, source_type, accessed_on, content, "html",
                             hashlib.sha256(data).hexdigest(), {"headings": parser.headings},
                             published_on=_declared_date(parser.published_candidates),
                             **(classification or {}))


def extract_pdf(data: bytes, *, url: str, allowed_hosts: tuple[str, ...], accessed_on: date,
                source_type: str = "official", classification: dict | None = None) -> ExtractedDocument:
    _validate_public_https(url, allowed_hosts)
    try:
        from pypdf import PdfReader
        reader = PdfReader(io.BytesIO(data))
        pages = [_clean(page.extract_text() or "") for page in reader.pages]
    except Exception as exc:
        raise ExtractionError("invalid or unreadable PDF") from exc
    content = "\n".join(f"[page {i}]\n{text}" for i, text in enumerate(pages, 1) if text)
    if not content:
        raise ExtractionError("PDF has no extractable text; OCR/review is required")
    title = str(reader.metadata.title or url.rsplit("/", 1)[-1]).strip()
    locator = f"pdf:pages-1-{len(reader.pages)}"
    return ExtractedDocument(title, url, source_type, accessed_on, content, locator,
                             hashlib.sha256(data).hexdigest(), {"pages": len(reader.pages)},
                             **(classification or {}))
