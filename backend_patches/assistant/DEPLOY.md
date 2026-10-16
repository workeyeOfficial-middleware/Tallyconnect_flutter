# AI Assistant — server AI key and free token allowance: deployment

Nothing has been deployed, run against a database, built or committed.

## What changed
- **Server key.** Users no longer enter an AI key. One provider, model and key are
  set in the backend `.env`. The key is never sent to the app, logged or returned.
- **Same data rules.** Answers still use only the user's account and active company.
  Team users still see only their permitted ledgers and vouchers. The assistant
  remains read-only.
- **Allowance per login.** Each login gets **10,000 free tokens** (the `free` row in
  `ai_plans`).
  - Usage comes from the provider's own token figures for every call, including the
    tool rounds. It is stored in `ai_usage`, so it applies across devices and
    sessions.
  - If a provider reports no figure, the call is estimated at about 4 characters per
    token and marked `estimated`.
- **When it runs out.** `/ask` answers **402** with `code: ai_quota_exhausted` and
  the message "Your free AI access has ended. Upgrade your plan to continue." The AI
  provider is not called.
  - The app shows a popup with **View plans**, which opens the Plans screen.
  - The chat input is replaced by a banner.
- **Limit checks.** The limit is checked before each question. A question that
  starts with tokens left is answered in full, so it can go a little over. The next
  question is refused.
- **One question at a time per login.** A second question during an answer gets 429
  `busy`, so two devices can't spend tokens in parallel.
- **Provider problems.** A bad key, no credit or a retired model shows users a
  neutral message (503 `ai_unavailable` or `ai_busy`). It never says "your key" and
  never returns 401. The details go to the server log with the key masked.
- **Older app versions.** They still send their own key. The server ignores it.
  `/providers`, `/verify` and `/models` answer from the server's settings, and
  questions use the server key and count against that user's tokens.

## 1. Database (staging first; additive only)
Run `sql/2026-10-14_ai_usage.sql`. It:
- creates `ai_plans`, `ai_usage` and `ai_usage_log`;
- inserts the `free` plan (10,000 tokens, lifetime).

It changes no existing data.

## 2. Backend `.env`
```
AI_PROVIDER=gemini            # gemini | openai | anthropic | groq | openrouter | mistral | deepseek
AI_API_KEY=<your provider key>
AI_MODEL=                     # optional, e.g. gemini-2.5-flash; empty = best model of the key
AI_FREE_TOKENS=10000          # only used if the 'free' plan row is missing
ASSISTANT_RATE_LIMIT_PER_10_MIN=30
```
If `AI_PROVIDER=gemini`, an existing `GEMINI_API_KEY` / `GEMINI_MODEL` also works.
With no key set, the assistant shows "not available" and nothing is called.

## 3. Backend files (in `TallyConnect-push/tally-backend`, uncommitted)
- New: `utils/aiUsage.js`.
- Changed: `utils/assistantRouter.js`, `utils/assistantCore.js`, `utils/aiProviders.js`.
- Changed: `.env.example` (names only, no values).
- Unchanged: `routes/assistant.js`, `server.js`.

Then `git pull` and `docker compose up -d --build` on the server. There are no new
npm packages.

## 4. App
- The assistant sheet: chat plus a tokens-left meter.
- The "free AI access ended" popup and banner.
- No key field, provider chips or model picker.
- Keys saved by older versions are deleted from the phone the first time the
  assistant is opened.

## Plans later
- More tokens for one user:
  `UPDATE ai_usage SET token_limit_override = 50000 WHERE user_id = <id>;`
- A paid plan:
  `INSERT INTO ai_plans (code, name, token_limit, period) VALUES ('pro','Pro',500000,'month');`
  then set the user's `plan_code`. A `month` plan restarts at 0 each month.
- Usage per user and per call: `ai_usage`, `ai_usage_log`.

The Plans screen still shows "Plan prices and switching are not available from the
server yet". Buying a plan in the app is a separate piece of work.

## Endpoints
- `GET /api/assistant/status` → `{enabled, provider:{id,label}, usage:{plan, limit, used, remaining, exhausted}}`
- `POST /api/assistant/ask {question, history}` → `{answer, blocks, tools_used, tokens_used, usage}`; 402 when used up.
