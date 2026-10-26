"""Suggestions from Claude: a description (alt text) for a photo, and a
search description for a page. Always suggestions — they fill the field,
you edit or keep them. Off unless ANTHROPIC_API_KEY is set."""

from __future__ import annotations

import base64
import logging
import os
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps

from . import config

log = logging.getLogger("cms.ai")

# The model, and how hard it thinks: describing a photo is simple work
MODEL = os.environ.get("CMS_AI_MODEL", "claude-opus-5-5")
EFFORT = os.environ.get("CMS_AI_EFFORT", "low")
SEND_SIDE = 1024          # photos are sent at most this big (enough to describe, fewer tokens)

ARTIST = ("Dominik Zarzycki, a textile artist and painter in Edinburgh: tapestries in handspun, "
          "naturally dyed wool, paintings, drawings and generative art.")


class Unavailable(RuntimeError):
    """Shown to the user as is."""


def enabled() -> bool:
    return bool(config.ANTHROPIC_API_KEY)


def _client():
    import anthropic
    if not enabled():
        raise Unavailable("Suggestions are off: no Claude API key is set on the server.")
    return anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY, timeout=60.0, max_retries=2)


def _ask(content: list[dict], max_tokens: int = 1024) -> str:
    import anthropic
    client = _client()
    try:
        response = client.beta.messages.create(
            model=MODEL,
            max_tokens=max_tokens,
            output_config={"effort": EFFORT},
            # a declined request is retried on Anthropic's recommended model
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            system=("You write short texts for an artist's portfolio website: " + ARTIST +
                    " Reply with the requested text only: no quotes, no preamble, no notes."),
            messages=[{"role": "user", "content": content}],
        )
    except anthropic.AuthenticationError:
        log.error("Claude API key rejected")
        raise Unavailable("The Claude API key was rejected. Check ANTHROPIC_API_KEY on the server.")
    except anthropic.PermissionDeniedError:
        raise Unavailable("The Claude API key isn't allowed to use this model.")
    except anthropic.RateLimitError:
        raise Unavailable("Claude is busy right now (rate limit). Try again in a minute.")
    except anthropic.APITimeoutError:
        raise Unavailable("Claude took too long to answer. Try again.")
    except anthropic.BadRequestError as e:
        log.error("Claude rejected the request: %s", e.message)
        raise Unavailable("Claude couldn't handle this request.")
    except anthropic.APIStatusError as e:
        log.error("Claude API error %s: %s", e.status_code, e.message)
        raise Unavailable("Claude had a problem. Try again later.")
    except anthropic.APIConnectionError:
        raise Unavailable("Couldn't reach Claude (network). Try again later.")

    if response.stop_reason == "refusal":
        raise Unavailable("Claude declined to describe this. Write it yourself.")
    text = " ".join(b.text for b in response.content if b.type == "text").strip()
    if not text:
        raise Unavailable("Claude returned nothing. Try again.")
    return text.strip('"“”').strip()


def _image_block(path: Path) -> dict:
    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img)
        img.thumbnail((SEND_SIDE, SEND_SIDE))
        buf = BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=85)
    return {"type": "image",
            "source": {"type": "base64", "media_type": "image/jpeg",
                       "data": base64.standard_b64encode(buf.getvalue()).decode()}}


def alt_text(site_path: str, context: str) -> str:
    """A description of a photo under site/, for screen readers and Google."""
    path = (config.SITE / site_path.lstrip("/")).resolve()
    if config.SITE not in path.parents or not path.is_file():
        raise Unavailable("That image isn't on the site.")
    return _ask([
        _image_block(path),
        {"type": "text", "text": (
            f"This photo appears on the page: {context or 'the portfolio'}.\n"
            "Write its alt text: one plain sentence, under 125 characters, describing what is "
            "visible (the work, the process, the materials, the colours) for someone who can't "
            "see it. Use the work's title if the photo shows it. Don't start with \"Image of\" "
            "or \"Photo of\", and don't guess facts the photo doesn't show.")},
    ], max_tokens=1024)


def page_description(title: str, details: str) -> str:
    """A search description (meta description) from the page's own text."""
    return _ask([{"type": "text", "text": (
        f"Page title: {title}\n\nWhat the page says:\n{details[:6000]}\n\n"
        "Write the page's search description (what Google shows under the link): "
        "one or two sentences, 120 to 155 characters, saying what the page shows, naming "
        "Dominik Zarzycki once. Use only facts from the page text above.")}],
        max_tokens=1024)
