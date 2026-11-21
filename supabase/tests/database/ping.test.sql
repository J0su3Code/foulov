begin;
select plan(2);
select is((select public.ping()), 'ok', 'ping répond ok');
select ok(has_function_privilege('anon', 'public.ping()', 'execute'), 'ping est appelable sans compte');
select * from finish();
rollback;
