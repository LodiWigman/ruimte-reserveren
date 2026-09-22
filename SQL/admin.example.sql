-- VOORBEELD; vervang het ID uitsluitend na gecontroleerde verificatie in Clerk.
-- Uitvoeren door de databasebeheerder, niet via de browser/Data API.
-- De huidige concrete waarde staat lokaal in admin.local.sql.
INSERT INTO public.profiles(id,display_name,role)
VALUES ('VERVANG_DOOR_GECONTROLEERD_CLERK_USER_ID','Beheerder','admin');
-- Deze placeholder voldoet bewust niet aan de Clerk-ID-constraint.
