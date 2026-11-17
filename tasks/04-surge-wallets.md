# 04 - SurgeWallets (Pipeline C)

Phase 2C. Starts after `core-v1`. Owns `Packages/SurgeWallets` only. Branch: `feat/surge-wallets`.

Read: PRD sections 5, 6.1 (balance modifiers), 8, 11.1. TRD sections 4, 9, 11, 13.

## Goal

Poll prepaid balances every 60 seconds and publish them. Implement `WalletPolling` from SurgeCore.

## Key requirements (TRD 9)

- DeepSeek: `GET https://api.deepseek.com/user/balance` with the user's own API key.
- OpenRouter: `GET https://openrouter.ai/api/v1/auth/key` for cumulative usage and remaining limit. Optionally `GET /api/v1/generation?id=<gen_id>` to reconcile the exact cost of one call.
- Anthropic: no public balance endpoint. Report `balanceUnavailable` for any account with no configured endpoint. Never an error.
- Poll cadence 60 seconds. Record `lastPolledAt` so every surface shows the same "updated 12s ago" clock.
- Retry with capped exponential backoff. A provider outage degrades that one account to "Balance unavailable". It never crashes the app or blocks other accounts.
- Keys come from the macOS Keychain only. Never from a file, plist or UserDefaults. Read through a small key-provider boundary so tests do not touch the real Keychain.

## Thresholds (PRD 6.1)

Low is under $5 per account (adjustable). Empty is under $0.50. These are modifiers the state store applies. Wallets only reports the amount, or unavailable.

## Business logic to test (mock HTTP responses)

- Successful parse for each provider's real response shape
- 401, timeout and malformed JSON each degrade to unavailable for that account only
- Backoff grows and caps, and resets after a success
- An unconfigured provider returns `balanceUnavailable` without any network call
- The poll interval is injected so tests do not wait

## Ask the user before deciding

- Exact JSON field to use for each provider's balance (confirm against the live API with the user's key, or sample responses).
- Whether OpenRouter balance is credits remaining or limit remaining when a key has a spend limit.

## Definition of done

Both providers parse and poll, fallback behaves as above, tests and lint pass, nothing outside the package touched.
