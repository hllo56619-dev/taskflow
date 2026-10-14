package com.minh.taskflow

/**
 * Fill these values with the same Supabase project used by web/config.js.
 * A publishable key (or legacy anon key) is intended for client apps when RLS is enabled.
 * NEVER put a service_role / secret key here.
 */
object AppConfig {
    const val SUPABASE_URL = "https://YOUR-PROJECT-ID.supabase.co"
    const val SUPABASE_ANON_KEY = "YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY"
}
