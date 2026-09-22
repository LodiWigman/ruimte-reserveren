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
SELECT id,display_name,role FROM public.profiles WHERE role='admin';
SELECT count(*) AS confirmed FROM public.reserveringen;
SELECT count(*) AS requests FROM public.reserveringsverzoeken;
