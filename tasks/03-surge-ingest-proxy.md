# 03 - SurgeIngestProxy (Pipeline B)

Phase 2B. Starts after `core-v1`. Owns `Packages/SurgeIngestProxy` only. Branch: `feat/surge-ingest-proxy`.

Read: PRD sections 5, 6.2, 11.1, 13. TRD sections 4, 8, 11, 13, 16.

## Goal

A local HTTP pass-through proxy that lets Surge observe DeepSeek and OpenRouter worker traffic. Implement `WorkerTraffic` from SurgeCore.

## Key requirements (TRD 8)

- `NWListener` (Network.framework) on `127.0.0.1:8899`. Bind to localhost only, never `0.0.0.0`.
- Routes: `http://127.0.0.1:8899/deepseek` goes to `https://api.deepseek.com`, `/openrouter` goes to `https://openrouter.ai/api/v1`. Workers set `OPENAI_BASE_URL` to the route.
- Strip the route prefix, forward the exact headers (including the caller's own `Authorization: Bearer ...`) and body, and stream the response back untouched. Never substitute Surge's own key.
- While chunks pass through, read the final SSE event or JSON body for the `usage` object (`prompt_tokens`, `completion_tokens`, `prompt_cache_hit_tokens`) and the exact model ID. Do this without delaying or altering the stream.
- Link the worker to a workspace: take the local socket's PID and call `proc_pidinfo` (libproc) to get its working directory, so it nests under the orchestrator in the same project folder.
- Emit `ProxyEvent` values on an `AsyncStream`. A worker appears within 5 seconds of its first request (PRD 11.1).

## Constraints

- No TLS interception. The proxy speaks plain HTTP to the worker and is an ordinary HTTPS client upstream.
- Never log or store request or response bodies. Keep only usage numbers and metadata.
- Imports `SurgeCore` only. Do not read the tailer, wallets or state store.
- If the port is taken or the listener fails, surface a state the app can show as "No signal" with a reason, not a crash.

## Business logic to test (in-process mock upstream server)

- Headers and body reach the upstream byte for byte, including `Authorization`, and the response comes back unchanged
- Route prefix stripping for `/deepseek` and `/openrouter`
- Usage extraction from a streamed SSE response and from a plain JSON response
- Responses with no usage object produce no bogus numbers
- PID to working directory linking (inject the libproc call behind a small boundary)
- Listener refuses non-localhost binding

## Ask the user before deciding

- How a worker's parent is chosen when two orchestrators run in the same workspace.
- Behaviour for unknown route prefixes (reject, or forward generically under "Other").

## Definition of done

Proxy works end to end against the mock upstream, tests and lint pass, nothing outside the package touched.
