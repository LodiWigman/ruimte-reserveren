-- Generated with Supabase CLI. Additive; apply after overview_cases_filters.
-- Help preferences confer no permissions and never modify profiles or bookings.
BEGIN;
CREATE TABLE public.help_progress (
  user_id text NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  guide_key text NOT NULL CHECK (
    guide_key ~ '^v1:(intro:(extern|intern|admin)|tab:(overzicht|reserveren|mijn|rollen|vragen|beheer):(extern|intern|admin|shared)|tip:notifications:(extern|intern|admin))$'
  ),
  outcome text NOT NULL CHECK (outcome IN ('completed','skipped')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,guide_key)
);
ALTER TABLE public.help_progress ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.help_progress FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.help_progress TO authenticated;
CREATE POLICY help_read_own ON public.help_progress FOR SELECT TO authenticated
  USING (user_id=(SELECT han_private.uid()));
CREATE POLICY help_insert_own ON public.help_progress FOR INSERT TO authenticated
  WITH CHECK (user_id=(SELECT han_private.uid()));

-- Invoker functions use the same RLS as direct API access. No client-supplied owner.
CREATE FUNCTION public.han_help_progress() RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT coalesce(jsonb_agg(guide_key ORDER BY guide_key),'[]'::jsonb)
  FROM public.help_progress WHERE user_id=(SELECT han_private.uid());
$$;
CREATE FUNCTION public.han_help_mark(guide_key text,outcome text) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE caller text := han_private.uid();
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'Log opnieuw in' USING ERRCODE='42501'; END IF;
  INSERT INTO public.help_progress(user_id,guide_key,outcome)
  VALUES (caller,guide_key,outcome) ON CONFLICT ON CONSTRAINT help_progress_pkey DO NOTHING;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.han_help_progress(),public.han_help_mark(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.han_help_progress(),public.han_help_mark(text,text) TO authenticated;
COMMENT ON TABLE public.help_progress IS 'Own-account, append-only help acknowledgements. Never an authorization source.';
COMMIT;
