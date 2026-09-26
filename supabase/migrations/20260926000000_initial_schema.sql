-- =============================================================================
-- CRADI / EWER — Supabase PostgreSQL Schema Migration
-- Matches Firestore Collections, Indices, and Security Model
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- 1. USERS & PROFILES TABLE
-- Mirrors Firestore `users/{uid}` collection & integrates with Supabase auth.users
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    phone TEXT,
    phone_number TEXT,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'user' CHECK (
        role IN ('user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'techSupport', 'admin')
    ),
    state TEXT,
    lga TEXT,
    ward TEXT,
    community TEXT,
    address TEXT,
    fcm_token TEXT,
    onesignal_player_id TEXT,
    avatar_url TEXT,
    profile_image_url TEXT,
    monitoring_zone TEXT,
    registration_code TEXT,
    is_approved BOOLEAN DEFAULT false,
    is_verified BOOLEAN DEFAULT false,
    is_disabled BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    biometrics_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    last_login_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- =============================================================================
-- 2. REPORTS TABLE
-- Mirrors Firestore `reports/{reportId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    hazard_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'validated', 'resolved', 'rejected')),
    state TEXT NOT NULL,
    lga TEXT NOT NULL,
    ward TEXT,
    community TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_description TEXT,
    description TEXT,
    image_urls TEXT[] DEFAULT '{}',
    voice_note_url TEXT,
    verification_count INT DEFAULT 0,
    rejection_count INT DEFAULT 0,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    validated_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Indexing for performance and matching Firestore composite indices
CREATE INDEX IF NOT EXISTS idx_reports_user_submitted ON public.reports (user_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_status_submitted ON public.reports (status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_state_submitted ON public.reports (state, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_state_status_submitted ON public.reports (state, status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_lga_status_submitted ON public.reports (lga, status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_ward_status ON public.reports (ward, status);

-- =============================================================================
-- 3. VERIFICATIONS TABLE
-- Mirrors Firestore `verifications/{verificationId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES public.reports(id) ON DELETE CASCADE,
    verifier_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_confirmed BOOLEAN NOT NULL DEFAULT true,
    comments TEXT,
    evidence_image_urls TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE(report_id, verifier_id)
);

CREATE INDEX IF NOT EXISTS idx_verifications_report ON public.verifications (report_id);
CREATE INDEX IF NOT EXISTS idx_verifications_verifier ON public.verifications (verifier_id);

-- =============================================================================
-- 4. ALERTS TABLE (Community broadcasts)
-- Mirrors Firestore `alerts/{alertId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    hazard_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'high' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    target_state TEXT,
    target_lga TEXT,
    target_ward TEXT,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_alerts_state_lga ON public.alerts (target_state, target_lga, is_active);

-- =============================================================================
-- 5. EMERGENCY CONTACTS TABLE
-- Mirrors Firestore `contacts/{contactId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    relationship TEXT,
    agency_or_department TEXT,
    state TEXT,
    lga TEXT,
    is_primary BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_contacts_user ON public.emergency_contacts (user_id);

-- =============================================================================
-- 6. KNOWLEDGE BASE / GUIDES TABLE
-- Mirrors Firestore `knowledge_base/{guideId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.knowledge_base (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    content TEXT NOT NULL,
    language TEXT NOT NULL DEFAULT 'en',
    thumbnail_url TEXT,
    is_published BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- =============================================================================
-- 7. CHAT & MESSAGES TABLES
-- Mirrors Firestore `messages/{messageId}` & `chats/{chatId}`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id TEXT NOT NULL,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    sender_name TEXT,
    content TEXT NOT NULL,
    media_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON public.messages (chat_id, created_at DESC);

-- =============================================================================
-- 8. TRUSTED DEVICES & LOGIN HISTORY
-- Mirrors Firestore `trusted_devices` & `login_history`
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.trusted_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_name TEXT,
    platform TEXT,
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE(user_id, device_id)
);

CREATE TABLE IF NOT EXISTS public.login_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ip_address TEXT,
    device_info TEXT,
    login_time TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    status TEXT NOT NULL DEFAULT 'success'
);

-- =============================================================================
-- 9. OTP VERIFICATIONS & OVERRIDES & NDPA CONSENTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.otp_verifications (
    id TEXT PRIMARY KEY,
    identifier TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    used BOOLEAN NOT NULL DEFAULT false,
    attempts INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.verification_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID REFERENCES public.reports(id) ON DELETE CASCADE,
    override_status TEXT NOT NULL,
    reason TEXT,
    overridden_by UUID REFERENCES public.profiles(id),
    overridden_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.ndpa_consents (
    id TEXT PRIMARY KEY,
    uid TEXT NOT NULL,
    consented_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    policy_version TEXT,
    data_residency TEXT,
    platform TEXT,
    method TEXT
);

-- =============================================================================
-- 10. STORAGE BUCKETS (Supabase Storage)
-- =============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('profile_images', 'profile_images', true),
       ('report_images', 'report_images', true)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 11. ROW LEVEL SECURITY (RLS) POLICIES
-- Strict policies mirroring Firestore security rules
-- =============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trusted_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ndpa_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public OTP checks and updates"
ON public.otp_verifications FOR ALL TO anon, authenticated
USING (true) WITH CHECK (true);

CREATE POLICY "Allow public NDPA consent inserts"
ON public.ndpa_consents FOR ALL TO anon, authenticated
USING (true) WITH CHECK (true);

-- Helper: Get user role
CREATE OR REPLACE FUNCTION public.get_current_role()
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- PROFILES POLICIES
CREATE POLICY "Public profiles are readable by authenticated users"
ON public.profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- REPORTS POLICIES
CREATE POLICY "Authors and staff can read reports"
ON public.reports FOR SELECT TO authenticated
USING (
    user_id = auth.uid() OR
    public.get_current_role() IN ('ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
);

CREATE POLICY "Authenticated users can submit reports"
ON public.reports FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Authors or verifiers can update reports"
ON public.reports FOR UPDATE TO authenticated
USING (
    (user_id = auth.uid() AND status = 'pending') OR
    public.get_current_role() IN ('ewm', 'ewv', 'ewr', 'ldp_coordinator', 'admin')
);

-- VERIFICATIONS POLICIES
CREATE POLICY "Verifiers can view verifications"
ON public.verifications FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Staff can insert verifications"
ON public.verifications FOR INSERT TO authenticated
WITH CHECK (
    verifier_id = auth.uid() AND
    public.get_current_role() IN ('ewm', 'ewv', 'ewr', 'admin')
);

-- ALERTS POLICIES
CREATE POLICY "Everyone authenticated can read alerts"
ON public.alerts FOR SELECT TO authenticated
USING (is_active = true);

CREATE POLICY "Only staff can manage alerts"
ON public.alerts FOR ALL TO authenticated
USING (public.get_current_role() IN ('ewv', 'ewr', 'ldp_coordinator', 'admin', 'techSupport'));

-- KNOWLEDGE BASE POLICIES
CREATE POLICY "Everyone authenticated can read published guides"
ON public.knowledge_base FOR SELECT TO authenticated
USING (is_published = true);

CREATE POLICY "Only admins can edit knowledge base"
ON public.knowledge_base FOR ALL TO authenticated
USING (public.get_current_role() IN ('admin', 'techSupport'));

-- STORAGE POLICIES
CREATE POLICY "Public read for report images"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id IN ('profile_images', 'report_images'));

CREATE POLICY "Authenticated users can upload images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id IN ('profile_images', 'report_images'));
