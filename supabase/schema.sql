-- ==============================================================================
-- MOTO-TOURING NAVIGATION & TELEMETRY PLATFORM
-- Supabase PostgreSQL + PostGIS Schema & Security Configuration
-- ==============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. Profiles Table (Rider Profile & Bike Specs)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    motorcycle_model TEXT,
    emergency_contact TEXT,
    blood_type VARCHAR(5),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Touring Routes Table (Pre-planned or Saved Corridors)
CREATE TABLE IF NOT EXISTS public.touring_routes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    origin_name TEXT NOT NULL,
    destination_name TEXT NOT NULL,
    origin_geom GEOMETRY(Point, 4326) NOT NULL,
    destination_geom GEOMETRY(Point, 4326) NOT NULL,
    route_corridor_geojson JSONB NOT NULL, -- GeoJSON LineString for offline corridor download
    bounding_box JSONB NOT NULL, -- [minX, minY, maxX, maxY] for tile pack caching
    estimated_distance_meters DOUBLE PRECISION NOT NULL,
    estimated_duration_seconds INTEGER NOT NULL,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index spatial data for lightning-fast geo-lookups
CREATE INDEX IF NOT EXISTS idx_touring_routes_origin_geom ON public.touring_routes USING GIST (origin_geom);
CREATE INDEX IF NOT EXISTS idx_touring_routes_destination_geom ON public.touring_routes USING GIST (destination_geom);

-- 4. Trip Sessions Table (Historical & Completed Rides)
CREATE TABLE IF NOT EXISTS public.trip_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    route_id UUID REFERENCES public.touring_routes(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    start_timestamp BIGINT NOT NULL,     -- Unix Timestamp (ms) at 'Start' trigger
    finish_timestamp BIGINT NOT NULL,    -- Unix Timestamp (ms) at 'Finish' trigger
    actual_duration_seconds INTEGER NOT NULL, -- Calculated strictly as (finish - start) / 1000
    total_distance_km DOUBLE PRECISION NOT NULL,
    avg_speed_kmh DOUBLE PRECISION NOT NULL,
    max_speed_kmh DOUBLE PRECISION NOT NULL,
    weather_condition TEXT,
    shareable_image_url TEXT,            -- URL of the rendered map snapshot + telemetry card
    sync_status VARCHAR(20) DEFAULT 'SYNCED',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trip_sessions_user ON public.trip_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_trip_sessions_created ON public.trip_sessions(created_at DESC);

-- 5. Trip GPS Breadcrumbs (Synchronized in batches after trip finishes)
CREATE TABLE IF NOT EXISTS public.trip_gps_breadcrumbs (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES public.trip_sessions(id) ON DELETE CASCADE,
    timestamp BIGINT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    speed_ms DOUBLE PRECISION,
    heading DOUBLE PRECISION
);

CREATE INDEX IF NOT EXISTS idx_breadcrumbs_session ON public.trip_gps_breadcrumbs(session_id);

-- 6. Voice Rooms Table (Intercom / Squad Channel)
CREATE TABLE IF NOT EXISTS public.voice_rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_by UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_name VARCHAR(100) UNIQUE NOT NULL,
    passcode VARCHAR(10),
    livekit_room_sid TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Heartbeat / Keep-Alive Ping Table (To prevent Supabase Free Tier auto-pause)
CREATE TABLE IF NOT EXISTS public._keep_alive_ping (
    id INT PRIMARY KEY DEFAULT 1,
    last_ping TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO public._keep_alive_ping (id, last_ping)
VALUES (1, NOW())
ON CONFLICT (id) DO UPDATE SET last_ping = NOW();

-- RPC function for external cron ping (UptimeRobot / cron-job.org)
CREATE OR REPLACE FUNCTION public.ping_keep_alive()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public._keep_alive_ping SET last_ping = NOW() WHERE id = 1;
    RETURN jsonb_build_object('status', 'OK', 'timestamp', NOW());
END;
$$;

-- 8. Row Level Security (RLS) Configuration
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.touring_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_gps_breadcrumbs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voice_rooms ENABLE ROW LEVEL SECURITY;

-- Profiles: Public can view, owner can update
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles
    FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

-- Touring Routes: Public routes viewable by all, users manage their own
CREATE POLICY "Public or owned routes viewable" ON public.touring_routes
    FOR SELECT USING (is_public OR auth.uid() = user_id);
CREATE POLICY "Users can insert routes" ON public.touring_routes
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own routes" ON public.touring_routes
    FOR UPDATE USING (auth.uid() = user_id);

-- Trip Sessions: Strictly private to user
CREATE POLICY "Users can view own trips" ON public.trip_sessions
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own trips" ON public.trip_sessions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Breadcrumbs: Accessible only by session owner
CREATE POLICY "Users can insert breadcrumbs for their sessions" ON public.trip_gps_breadcrumbs
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.trip_sessions 
            WHERE trip_sessions.id = trip_gps_breadcrumbs.session_id 
            AND trip_sessions.user_id = auth.uid()
        )
    );
CREATE POLICY "Users can view their breadcrumbs" ON public.trip_gps_breadcrumbs
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.trip_sessions 
            WHERE trip_sessions.id = trip_gps_breadcrumbs.session_id 
            AND trip_sessions.user_id = auth.uid()
        )
    );

-- Voice rooms: Authenticated users can read active rooms & create
CREATE POLICY "Authenticated users view active rooms" ON public.voice_rooms
    FOR SELECT TO authenticated USING (is_active = true);
CREATE POLICY "Authenticated users create rooms" ON public.voice_rooms
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);
