-- DESTRUCTIEF. Samen met basis, startgegevens en adminherstel in EEN transactie.
-- Bewust geen CASCADE: onverwachte afhankelijkheden blokkeren de reset.
DROP TABLE public.reserveringen, public.reserveringsverzoeken, public.role_requests, public.support_messages, public.profiles, public.rooms;
DROP FUNCTION private.assert_admin();
DROP FUNCTION private.is_admin();
DROP FUNCTION private.is_intern();
DROP FUNCTION public.approve_reserveringsverzoek(uuid, text);
DROP FUNCTION public.approve_reserveringsverzoek_reeks(uuid, text);
DROP FUNCTION public.approve_role_request(uuid);
DROP FUNCTION public.current_clerk_user_id();
DROP FUNCTION public.import_reserveringen(jsonb);
DROP FUNCTION public.public_reserveringen_overzicht();
DROP FUNCTION public.public_reserveringsverzoeken();
DROP FUNCTION public.reject_reserveringsverzoek(uuid, text);
DROP FUNCTION public.reject_reserveringsverzoek_reeks(uuid, text);
DROP FUNCTION public.reject_role_request(uuid);
DROP FUNCTION public.set_updated_at();
