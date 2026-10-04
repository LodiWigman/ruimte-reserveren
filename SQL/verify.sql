-- Alleen lezen; uitvoeren na de goedgekeurde release.
SELECT current_database(),version();
SELECT relname,relrowsecurity FROM pg_class
WHERE relnamespace='public'::regnamespace AND relkind='r' ORDER BY relname;
SELECT tablename,policyname,cmd,roles,qual,with_check FROM pg_policies
WHERE schemaname='public' ORDER BY tablename,policyname;
SELECT table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='public' AND grantee IN ('anon','authenticated') ORDER BY 1,2,3;
SELECT p.oid::regprocedure AS signature,p.prosecdef,p.proconfig,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','han_private','private')
AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
ORDER BY 1;
SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='public.reserveringen'::regclass;
SELECT count(*) AS rooms,count(*) FILTER(WHERE active) AS active_rooms FROM public.rooms;
SELECT count(*) AS admins FROM public.profiles WHERE role='admin';
SELECT count(*) AS confirmed FROM public.reserveringen;
SELECT count(*) AS requests FROM public.reserveringsverzoeken;

-- HAN@Connectr: alleen uitvoeren nadat de bijbehorende migratie is toegepast.
SELECT relname,relrowsecurity FROM pg_class
WHERE relnamespace='han_private'::regnamespace AND relkind='r' ORDER BY relname;
SELECT table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='han_private' AND grantee IN ('anon','authenticated'); -- verwacht: nul rijen
SELECT count(*) AS profiles,count(*) FILTER(WHERE name_confirmed_at IS NOT NULL) AS confirmed_names FROM public.profiles;
SELECT count(*) AS cases,count(*) FILTER(WHERE archived_at IS NOT NULL) AS archived FROM han_private.support_messages;
SELECT count(*) AS messages,count(*) FILTER(WHERE legacy) AS migrated_messages,
  count(*) FILTER(WHERE legacy AND created_at IS NULL) AS preserved_unknown_times FROM han_private.case_messages;
SELECT count(*) AS notifications FROM han_private.notifications;
SELECT count(*) AS transfers FROM han_private.transfers;
SELECT to_regclass('public.support_messages') IS NULL AS support_not_public;

-- Geen identiteiten of sessies uitlezen: alleen beveiligingsstructuur en aantallen.
SELECT issuer,origins FROM han_private.trusted_auth;
SELECT count(*) AS revoked_session_count FROM han_private.revoked_sessions;
SELECT count(*) AS blocked_account_count FROM han_private.blocked_accounts;
SELECT count(*) AS audit_event_count FROM han_private.audit_events;
SELECT event_object_schema,event_object_table,trigger_name,event_manipulation
FROM information_schema.triggers
WHERE trigger_name IN ('write_budget','audit_change') ORDER BY 1,2,3,4;
