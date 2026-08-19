#!/usr/bin/env python3
"""Probe an OpenAI-compatible gateway without changing SpringNote settings.

Examples (PowerShell):
  python tools/test_openai_interfaces.py --provider "OpenAI Responses" --use-config-key
  $env:SPRINGNOTE_API_KEY = "..."
  python tools/test_openai_interfaces.py --provider "OpenAI Responses"
  python tools/test_openai_interfaces.py --base-url https://api.example.com/v1 --api-key-env OPENAI_API_KEY

The script tests:
  * GET /models
  * POST /chat/completions (minimal, temperature, streaming)
  * POST /responses (minimal, temperature, reasoning, streaming)
  * POST /completions (legacy/FIM probe)

It only prints short response summaries; it never prints the API key.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


KNOWN_ENDPOINT_SUFFIXES = (
    "/chat/completions",
    "/responses",
    "/completions",
    "/messages",
)


@dataclass
class Provider:
    name: str
    base_url: str
    api_path: str
    api_key: str
    models: list[str]


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"配置文件不存在: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"配置文件不是有效 JSON: {path}: {exc}")


def default_config_path() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "SpringNote" / "config.json"
    return Path.home() / ".config" / "SpringNote" / "config.json"


def normalize_url(value: str) -> str:
    return value.strip().rstrip("/")


def join_url(base: str, path: str) -> str:
    base = normalize_url(base)
    path = path.strip().strip("/")
    return f"{base}/{path}" if path else base


def api_root(base_url: str, api_path: str) -> str:
    """Remove an endpoint suffix so /models can be probed reliably."""
    base = normalize_url(base_url)
    path = "/" + api_path.strip().strip("/") if api_path.strip() else ""
    combined = normalize_url(base + path)
    lower = combined.lower()
    for suffix in KNOWN_ENDPOINT_SUFFIXES:
        if lower.endswith(suffix):
            return combined[: -len(suffix)].rstrip("/")
    return combined


def provider_from_config(config: dict[str, Any], name: str | None) -> Provider:
    providers = config.get("providers") or []
    if not isinstance(providers, list):
        raise SystemExit("config.json 中 providers 不是数组")

    selected = None
    if name:
        for item in providers:
            if isinstance(item, dict) and item.get("name") == name:
                selected = item
                break
        if selected is None:
            available = [str(x.get("name")) for x in providers if isinstance(x, dict)]
            raise SystemExit(f"找不到供应商 {name!r}。可选值: {', '.join(available)}")
    else:
        selected = next(
            (x for x in providers if isinstance(x, dict) and x.get("enabled", True)),
            None,
        )
    if not isinstance(selected, dict):
        raise SystemExit("没有找到可用供应商，请使用 --base-url 手动指定")

    models = []
    for item in selected.get("models") or []:
        if isinstance(item, dict) and str(item.get("modelId", "")).strip():
            models.append(str(item["modelId"]).strip())

    return Provider(
        name=str(selected.get("name", "configured")),
        base_url=str(selected.get("baseUrl", "")),
        api_path=str(selected.get("apiPath", "")),
        api_key=str(selected.get("apiKey", "")),
        models=models,
    )


def short_json(value: Any, limit: int = 700) -> str:
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return text if len(text) <= limit else text[:limit] + "..."


def summarize_json(value: Any) -> str:
    if not isinstance(value, dict):
        return short_json(value)

    keys = ", ".join(value.keys())
    if isinstance(value.get("error"), dict):
        error = value["error"]
        message = error.get("message", short_json(error))
        return f"error.message={message!s}; keys=[{keys}]"

    if isinstance(value.get("data"), list):
        ids = [item.get("id") for item in value["data"] if isinstance(item, dict)]
        ids = [str(x) for x in ids if x]
        shown = ", ".join(ids[:30])
        if len(ids) > 30:
            shown += f", ... (+{len(ids) - 30})"
        return f"models={len(ids)} [{shown}]; keys=[{keys}]"

    if isinstance(value.get("output_text"), str):
        return f"output_text={value['output_text'][:240]!r}; keys=[{keys}]"

    choices = value.get("choices")
    if isinstance(choices, list) and choices:
        choice = choices[0] if isinstance(choices[0], dict) else {}
        message = choice.get("message") if isinstance(choice, dict) else None
        content = message.get("content") if isinstance(message, dict) else None
        return f"choice.content={str(content)[:240]!r}; keys=[{keys}]"

    return f"keys=[{keys}]; body={short_json(value)}"


def request_once(
    method: str,
    url: str,
    api_key: str,
    body: dict[str, Any] | None = None,
    timeout: float = 45,
) -> tuple[int | None, str, Any, float]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json, text/event-stream",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")

    request = Request(url, data=data, headers=headers, method=method)
    started = time.perf_counter()
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read()
            content_type = response.headers.get("Content-Type", "")
            status = response.status
    except HTTPError as exc:
        raw = exc.read()
        content_type = exc.headers.get("Content-Type", "") if exc.headers else ""
        status = exc.code
    except (URLError, TimeoutError, OSError) as exc:
        return None, "", f"network error: {exc}", time.perf_counter() - started

    text = raw.decode("utf-8", errors="replace")
    if "application/json" in content_type or text.lstrip().startswith(("{", "[")):
        try:
            return status, content_type, json.loads(text), time.perf_counter() - started
        except json.JSONDecodeError:
            pass
    return status, content_type, text, time.perf_counter() - started


def print_result(label: str, status: int | None, content_type: str, result: Any, elapsed: float) -> None:
    status_text = str(status) if status is not None else "N/A"
    if isinstance(result, str):
        body = result.replace("\r", "").replace("\n", "\\n")
        body = body if len(body) <= 700 else body[:700] + "..."
        summary = body
    else:
        summary = summarize_json(result)
    print(f"[{status_text:>3}] {elapsed * 1000:7.0f} ms  {label}")
    if content_type:
        print(f"      content-type: {content_type}")
    print(f"      {summary}")


def run_probe(provider: Provider, api_key: str, model: str, timeout: float) -> int:
    root = api_root(provider.base_url, provider.api_path)
    configured_endpoint = join_url(provider.base_url, provider.api_path)
    print(f"供应商: {provider.name}")
    print(f"Base URL: {normalize_url(provider.base_url)}")
    print(f"配置的 API Path: {provider.api_path or '(空)'}")
    print(f"实际配置端点: {configured_endpoint}")
    print(f"探测模型: {model}")
    print(f"探测根地址: {root}")
    print()

    results: list[tuple[str, int | None]] = []

    def probe(label: str, method: str, url: str, body: dict[str, Any] | None = None) -> None:
        status, content_type, result, elapsed = request_once(
            method, url, api_key, body=body, timeout=timeout
        )
        print_result(label, status, content_type, result, elapsed)
        results.append((label, status))

    print("== 1. 模型列表 ==")
    probe("GET /models", "GET", join_url(root, "/models"))
    print()

    chat_url = join_url(root, "/chat/completions")
    chat_base = {
        "model": model,
        "messages": [
            {"role": "system", "content": "Reply with OK only."},
            {"role": "user", "content": "Say OK."},
        ],
    }
    print("== 2. Chat Completions ==")
    probe("POST /chat/completions minimal", "POST", chat_url, chat_base)
    probe(
        "POST /chat/completions + temperature",
        "POST",
        chat_url,
        {**chat_base, "temperature": 0.2},
    )
    probe(
        "POST /chat/completions streaming",
        "POST",
        chat_url,
        {**chat_base, "stream": True},
    )
    print()

    responses_url = join_url(root, "/responses")
    responses_base = {
        "model": model,
        "instructions": "Reply with OK only.",
        "input": "Say OK.",
    }
    print("== 3. Responses API ==")
    probe("POST /responses minimal", "POST", responses_url, responses_base)
    probe(
        "POST /responses + temperature",
        "POST",
        responses_url,
        {**responses_base, "temperature": 0.2},
    )
    probe(
        "POST /responses + reasoning",
        "POST",
        responses_url,
        {**responses_base, "reasoning": {"effort": "medium"}},
    )
    probe(
        "POST /responses streaming",
        "POST",
        responses_url,
        {**responses_base, "stream": True},
    )
    print()

    completions_url = join_url(root, "/completions")
    print("== 4. Legacy Completions / FIM ==")
    probe(
        "POST /completions prompt+suffix",
        "POST",
        completions_url,
        {
            "model": model,
            "prompt": "def add(a, b):\n    ",
            "suffix": "\n",
            "max_tokens": 16,
        },
    )
    print()

    print("== 判断 ==")
    for label, status in results:
        if status is not None and 200 <= status < 300:
            verdict = "SUPPORTED/ACCEPTED"
        elif status == 400:
            verdict = "REACHED, BUT REQUEST/PARAMETER REJECTED"
        elif status in (401, 403):
            verdict = "AUTHORIZATION/ACCESS FAILED"
        elif status in (404, 405):
            verdict = "ENDPOINT OR MODEL NOT FOUND/NOT ALLOWED"
        elif status is None:
            verdict = "NETWORK FAILED"
        else:
            verdict = "FAILED"
        print(f"{verdict:44} {label}")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=default_config_path())
    parser.add_argument("--provider", help="config.json 中的供应商名称")
    parser.add_argument("--base-url", help="覆盖配置中的 Base URL")
    parser.add_argument("--api-path", help="覆盖配置中的 API Path")
    parser.add_argument("--model", help="覆盖探测模型 ID")
    parser.add_argument(
        "--api-key-env",
        default="SPRINGNOTE_API_KEY",
        help="从哪个环境变量读取 API Key；默认 SPRINGNOTE_API_KEY",
    )
    parser.add_argument(
        "--use-config-key",
        action="store_true",
        help="明确允许读取配置文件中的 API Key。不会打印 Key。",
    )
    parser.add_argument("--timeout", type=float, default=45.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = read_json(args.config)
    provider = provider_from_config(config, args.provider)

    if args.base_url:
        provider.base_url = args.base_url
    if args.api_path is not None:
        provider.api_path = args.api_path

    api_key = os.environ.get(args.api_key_env, "").strip()
    if not api_key and args.use_config_key:
        api_key = provider.api_key.strip()
    if not api_key:
        raise SystemExit(
            f"没有 API Key。请设置 ${args.api_key_env}，或显式添加 --use-config-key。"
        )
    if not provider.base_url.strip():
        raise SystemExit("Base URL 为空")

    model = args.model or (provider.models[0] if provider.models else "")
    if not model:
        raise SystemExit("没有模型 ID，请使用 --model 指定")

    return run_probe(provider, api_key, model, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
