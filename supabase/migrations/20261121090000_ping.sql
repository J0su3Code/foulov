-- Signe de vie quotidien (GitHub Actions, .github/workflows/supabase-ping.yml) : le plan gratuit de Supabase met en
-- pause un projet resté 7 jours sans activité. La fonction ne lit aucune table et ne renvoie que « ok ».
create or replace function public.ping()
returns text
language sql
stable
set search_path = ''
as $$ select 'ok'::text $$;

revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;
