# License Admin Portal

Internal web portal for issuing, monitoring, renewing, suspending, and revoking
POS licenses.

## First-time setup

1. Run `supabase_admin_portal_migration.sql` in the Supabase SQL Editor.
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
```

5. Copy `.env.example` to `.env` and provide the Supabase URL and publishable
   key.

## Local development

```powershell
npm install
npm run dev
```

## Production build

```powershell
npm run build
```
