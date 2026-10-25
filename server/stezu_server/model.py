"""Anthropic Messages API client. Base URL, key and model come from the env file."""

from __future__ import annotations

from typing import Any

from .config import Settings
from .net import HttpError


class ModelError(Exception):
    pass


class AnthropicClient:
    """Forces one tool call so the answer is JSON that matches the tool's schema."""

    def __init__(self, settings: Settings, http: Any) -> None:
        self.settings, self.http = settings, http
        self.model_id = settings.model

    def tool_call(self, system: str, content: list[dict[str, Any]], tool: dict[str, Any],
                  max_tokens: int = 1500) -> dict[str, Any]:
        key = self.settings.api_key()
        if not key:
            raise ModelError("no model API key configured")
        payload: dict[str, Any] = {
            "model": self.model_id,
            "max_tokens": max_tokens,
            "system": system,
            "messages": [{"role": "user", "content": content}],
            "tools": [tool],
            "tool_choice": {"type": "tool", "name": tool["name"]},
        }
        if self.settings.temperature is not None:
            payload["temperature"] = self.settings.temperature
        url = f"{self.settings.anthropic_base_url}/v1/messages"
        headers = {"x-api-key": key, "anthropic-version": "2023-06-01"}
        try:
            try:
                resp = self.http.post_json(url, payload, headers)
            except HttpError as exc:
                if exc.status != 400 or "temperature" not in exc.body or "temperature" not in payload:
                    raise
                payload.pop("temperature")  # some newer models reject the parameter
                resp = self.http.post_json(url, payload, headers)
        except HttpError as exc:
            raise ModelError(f"model call failed: HTTP {exc.status}") from exc
        except OSError as exc:
            raise ModelError(f"model call failed: {exc}") from exc
        for block in resp.get("content", []):
            if block.get("type") == "tool_use" and block.get("name") == tool["name"]:
                return block["input"]
        raise ModelError("model returned no structured result")
