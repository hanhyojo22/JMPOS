# License Admin Portal

Internal web portal for issuing, monitoring, renewing, suspending, and revoking
POS licenses.

## First-time setup

1. Run `supabase_admin_portal_migration.sql` and
   `supabase_password_reset_rate_limit_migration.sql` in the Supabase SQL
   Editor.
2. Create your developer account in Supabase Authentication.
3. Grant the account access:  

```sql
insert into public.license_admins (user_id)
select id from auth.users where email = 'YOUR_ADMIN_EMAIL'
on conflict do nothing;
```

4. Deploy the protected admin function:

```powershell
supabase functions deploy admin-license-management
supabase functions deploy sync-owner-password-reset
```

5. Copy `.env.example` to `.env` and provide the Supabase URL, publishable
   key, and password reset redirect URL. For local development, use
   `http://localhost:5173/reset-password`.
6. In Supabase Authentication email templates, set the Reset Password link to
   use a token hash so the web portal can verify resets requested from the POS
   app:

```html
<a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=recovery">
  Reset password
</a>
```

The local Supabase config uses `supabase/templates/recovery.html` for the same
flow.

## Local development

```powershell
npm install
npm run dev
```

## Production build

```powershell
npm run build
```
