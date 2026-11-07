# Supabase setup for BSNU Portal

This repository is hosted as a static GitHub Pages site. The Supabase backend is prepared separately so admin permissions and AI credentials are never trusted to browser-only code.

## 1. Create/connect the Supabase project
1. Create a Supabase project (or connect the existing one).
2. Apply `supabase/migrations/202611080001_portal_backend.sql` in the Supabase SQL Editor.
3. Create an Auth user for the site owner using Supabase Authentication.
4. In the SQL Editor, add that user's UUID to `public.portal_admins`:
   `insert into public.portal_admins (user_id) values ('YOUR_AUTH_USER_UUID');`
   Do not expose the service-role key or store a password in this repository.

## 2. Configure the AI function
Set these Supabase Edge Function secrets:
- `AI_API_URL`: OpenAI-compatible chat-completions endpoint.
- `AI_API_KEY`: provider API key (secret; never commit it).
- `AI_MODEL`: model identifier.

Deploy `supabase/functions/ai-chat/index.ts` as function `ai-chat` with JWT verification enabled. The function requires a signed-in Supabase user and keeps the model key server-side.

## 3. Frontend connection
The frontend integration requires the Supabase project URL and publishable/anon key. The publishable key is designed for browser use only when Row Level Security is enabled; it is not an admin secret. The website will not be switched to live Supabase reads/writes until a project is connected and the schema is applied.

## Security notes
- Never use the numeric password previously pasted in chat as an admin password.
- Use Supabase Auth, a unique password, and the `portal_admins` allowlist.
- Never put a service-role key or AI provider key in `index.html`.
- Public users can read published lectures, schedule and announcements. Only allowlisted admins can write.
