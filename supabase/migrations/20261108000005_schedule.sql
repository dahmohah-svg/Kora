-- Kora: scheduled jobs. Supabase provides pg_cron; skip quietly where it is
-- not available (local test database).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('kora-finalize-matches',  '*/10 * * * *', 'select public.finalize_due_matches()');
    perform cron.schedule('kora-cancel-unconfirmed', '*/5 * * * *',  'select public.cancel_unconfirmed_matches()');
    perform cron.schedule('kora-reminders',          '*/5 * * * *',  'select public.queue_reminders()');
  end if;
end;
$$;
