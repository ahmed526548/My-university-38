# Supabase setup — My University portal

This repository is a static GitHub Pages frontend. These files prepare the secure backend foundation; they do not contain project credentials or a hard-coded admin password.

## 1. Create a Supabase project
1. Create a project in your Supabase account.
2. Open **Project Settings → API** and copy the Project URL and publishable/anon key.
3. Keep the **service_role/secret key private**. Never paste it into `index.html`, GitHub, or a public chat.
4. In **Authentication → Providers**, enable Email sign-in and create your own admin user with a new, unique password.

## 2. Create database tables and storage
Run `supabase/migrations/202611080001_portal_foundation.sql` in the Supabase SQL Editor.

After creating the admin user in Authentication → Users, copy that user's UUID and run this one-time SQL (replace the UUID):
```sql
insert into public.user_roles (user_id, role)
values ('YOUR-AUTH-USER-UUID', 'admin')
on conflict (user_id) do update set role = 'admin';
```
Only assign the admin role to your own trusted account.

The migration creates subjects, lectures, schedule days/slots/items, announcements, portal settings, row-level security policies, and the `lecture-files` Storage bucket. Public users can read published content and lecture files; only admins can change portal data or upload/delete lecture files.

## 3. Configure and deploy the AI function
Set the following secrets in Supabase (Dashboard → Edge Functions → Secrets), or with the CLI:
```sh
supabase secrets set AI_API_URL=https://api.openai.com/v1/chat/completions
supabase secrets set AI_API_KEY=YOUR_PROVIDER_KEY
supabase secrets set AI_MODEL=gpt-4.1-mini
```
Deploy:
```sh
supabase functions deploy ai-chat
```
The function requires a valid Supabase user session. It keeps the model provider key on the server, validates input size, and returns the assistant answer in the `answer` field. It is not yet callable from the current website until its Supabase client and student sign-in flow are connected.

## 4. Frontend integration still required
The current `index.html` does not yet contain your Supabase Project URL/key or an authentication screen. After the project is created, connect the frontend using **Project URL + publishable/anon key only**. The admin page must check the signed-in user's role, while database RLS remains the actual security boundary.

## Security
- Do not use a shared numeric password in frontend JavaScript as admin protection.
- Never expose the Supabase service-role key or AI provider key in GitHub Pages.
- CORS is not authentication; database RLS and server-side role checks are the authorization controls.
- Add usage quotas/rate limits before enabling the AI assistant for unrestricted public use.
