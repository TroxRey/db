-- ============================================================
-- Esquema completo (schema full) PostgreSQL
-- Organización por dependencias:
--   1) Preambulo y SET
--   2) Schema
--   3) Tipos (ENUM)
--   4) Funciones y trigger functions
--   5) Tablas (y Secuencias/DEFAULTs)
--   6) Constraints (PK/UK)
--   7) Índices
--   8) Triggers
--   9) Claves Foráneas (FK)
--  10) Vistas
--  11) Grants/ACL
-- Versión de dump original: 17.5
-- ============================================================

-- PostgreSQL database dump

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2025-08-29 00:10:52

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- 2) Schema
-- Name: public; Type: SCHEMA; Owner: pg_database_owner
CREATE SCHEMA public;
ALTER SCHEMA public OWNER TO pg_database_owner;

COMMENT ON SCHEMA public IS 'standard public schema';

-- 3) Tipos (ENUM)
CREATE TYPE public.admin_role AS ENUM (
    'owner',
    'super_admin',
    'admin',
    'moderator',
    'support'
);
ALTER TYPE public.admin_role OWNER TO postgres;

CREATE TYPE public.adminrole AS ENUM (
    'owner',
    'super_admin',
    'admin',
    'moderator',
    'support'
);
ALTER TYPE public.adminrole OWNER TO postgres;

CREATE TYPE public.ban_type AS ENUM (
    'temporary',
    'permanent',
    'shadow'
);
ALTER TYPE public.ban_type OWNER TO postgres;

CREATE TYPE public.bantype AS ENUM (
    'temporary',
    'permanent',
    'shadow'
);
ALTER TYPE public.bantype OWNER TO postgres;

CREATE TYPE public.chat_type AS ENUM (
    'private',
    'group',
    'supergroup',
    'channel'
);
ALTER TYPE public.chat_type OWNER TO postgres;

CREATE TYPE public.chattype AS ENUM (
    'private',
    'group',
    'supergroup',
    'channel'
);
ALTER TYPE public.chattype OWNER TO postgres;

CREATE TYPE public.group_status AS ENUM (
    'active',
    'inactive',
    'suspended',
    'pending_activation'
);
ALTER TYPE public.group_status OWNER TO postgres;

CREATE TYPE public.group_status_enhanced AS ENUM (
    'active',
    'inactive',
    'suspended',
    'pending_activation',
    'maintenance'
);
ALTER TYPE public.group_status_enhanced OWNER TO postgres;

CREATE TYPE public.processing_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'cancelled'
);
ALTER TYPE public.processing_status OWNER TO postgres;

CREATE TYPE public.report_status AS ENUM (
    'pending',
    'under_review',
    'resolved',
    'dismissed',
    'escalated'
);
ALTER TYPE public.report_status OWNER TO postgres;

CREATE TYPE public.subscription_context AS ENUM (
    'global',
    'private',
    'group',
    'channel'
);
ALTER TYPE public.subscription_context OWNER TO postgres;

CREATE TYPE public.transaction_type AS ENUM (
    'purchase',
    'manual_add',
    'manual_subtract',
    'command_usage',
    'refund',
    'bonus',
    'penalty'
);
ALTER TYPE public.transaction_type OWNER TO postgres;

CREATE TYPE public.user_status AS ENUM (
    'active',
    'inactive',
    'suspended'
);
ALTER TYPE public.user_status OWNER TO postgres;

CREATE TYPE public.userstatus AS ENUM (
    'active',
    'inactive',
    'suspended'
);
ALTER TYPE public.userstatus OWNER TO postgres;

CREATE TYPE public.warning_type AS ENUM (
    'spam',
    'abuse',
    'violation',
    'manual',
    'automated'
);
ALTER TYPE public.warning_type OWNER TO postgres;

-- 4) Funciones y trigger functions
CREATE FUNCTION public.activate_group(p_group_id bigint, p_admin_id bigint, p_notes text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    admin_can_activate BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM user_roles ur
        JOIN role_permissions rp ON ur.role = rp.role
        WHERE ur.user_id = p_admin_id
          AND rp.permission_name = 'can_activate_groups'
          AND rp.is_allowed = TRUE
          AND ur.is_active = TRUE
    ) INTO admin_can_activate;

    IF NOT admin_can_activate THEN
        RETURN FALSE;
    END IF;

    UPDATE groups 
    SET status = 'active',
        activated_at = CURRENT_TIMESTAMP,
        activated_by = p_admin_id,
        activation_notes = p_notes
    WHERE group_id = p_group_id;

    RETURN TRUE;
END;
$$;
ALTER FUNCTION public.activate_group(p_group_id bigint, p_admin_id bigint, p_notes text) OWNER TO postgres;

CREATE FUNCTION public.admin_create_key_command(p_admin_id bigint, p_duration_text text, p_plan_name text, p_credits_text text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
AS $$
DECLARE
    duration_days INTEGER;
    plan_id INTEGER;
    bonus_credits INTEGER := 0;
    result_key TEXT;
BEGIN
    duration_days := SUBSTRING(p_duration_text FROM '^(\d+)')::INTEGER;

    SELECT sp.plan_id INTO plan_id
    FROM subscription_plans sp
    WHERE LOWER(sp.plan_name) = LOWER(p_plan_name) AND sp.is_active = TRUE;

    IF plan_id IS NULL THEN
        RETURN 'ERROR: Plan no encontrado: ' || p_plan_name;
    END IF;

    IF p_credits_text IS NOT NULL THEN
        bonus_credits := SUBSTRING(p_credits_text FROM '^(\d+)')::INTEGER;
    END IF;

    result_key := create_subscription_key(p_admin_id, plan_id, duration_days, bonus_credits, p_notes);

    IF LEFT(result_key, 5) = 'ERROR' THEN
        RETURN result_key;
    END IF;

    RETURN FORMAT('✅ Key creada exitosamente:
🔑 Código: `%s`
📅 Duración: %s días
📦 Plan: %s
💎 Créditos bonus: %s
📝 Notas: %s', 
        result_key, duration_days, p_plan_name, 
        COALESCE(bonus_credits::TEXT, '0'), 
        COALESCE(p_notes, 'Sin notas'));
END;
$$;
ALTER FUNCTION public.admin_create_key_command(p_admin_id bigint, p_duration_text text, p_plan_name text, p_credits_text text, p_notes text) OWNER TO postgres;

CREATE FUNCTION public.admin_give_credits_command(p_admin_id bigint, p_target_identifier text, p_credits_amount integer, p_reason text DEFAULT 'Créditos otorgados por admin'::text) RETURNS text
    LANGUAGE plpgsql
AS $$
DECLARE
    target_user_id BIGINT;
    target_username TEXT;
    success BOOLEAN;
BEGIN
    IF LEFT(p_target_identifier, 1) = '@' THEN
        SELECT user_id, username INTO target_user_id, target_username
        FROM users 
        WHERE username = SUBSTRING(p_target_identifier FROM 2)
          AND status = 'active';
    ELSE
        SELECT user_id, username INTO target_user_id, target_username
        FROM users 
        WHERE user_id = p_target_identifier::BIGINT
          AND status = 'active';
    END IF;

    IF target_user_id IS NULL THEN
        RETURN '❌ Usuario no encontrado: ' || p_target_identifier;
    END IF;

    success := give_credits_to_user(p_admin_id, target_user_id, p_credits_amount, p_reason);

    IF NOT success THEN
        RETURN '❌ Error: Sin permisos para otorgar créditos';
    END IF;

    RETURN FORMAT('✅ Créditos otorgados exitosamente:
👤 Usuario: %s (ID: %s)
💎 Cantidad: %s créditos
📝 Razón: %s',
        COALESCE('@' || target_username, 'Sin username'), 
        target_user_id, 
        p_credits_amount, 
        p_reason);
END;
$$;
ALTER FUNCTION public.admin_give_credits_command(p_admin_id bigint, p_target_identifier text, p_credits_amount integer, p_reason text) OWNER TO postgres;

CREATE FUNCTION public.audit_generic_crud_fn() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO audit_log (user_id, action, entity, entity_id, timestamp, details)
  VALUES (NULL, TG_OP, TG_TABLE_NAME, 
    CASE WHEN TG_OP = 'DELETE' THEN OLD.id::text ELSE NEW.id::text END,
    CURRENT_TIMESTAMP,
    CASE WHEN TG_OP = 'INSERT' THEN row_to_json(NEW)
         WHEN TG_OP = 'UPDATE' THEN json_build_object('old', row_to_json(OLD), 'new', row_to_json(NEW))
         WHEN TG_OP = 'DELETE' THEN row_to_json(OLD)
         ELSE NULL END
  );
  RETURN NULL;
END;
$$;
ALTER FUNCTION public.audit_generic_crud_fn() OWNER TO postgres;

CREATE FUNCTION public.can_user_execute_in_group(p_user_id bigint, p_group_id bigint, p_command_id integer) RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    group_active BOOLEAN;
    user_has_subscription BOOLEAN;
    user_banned BOOLEAN;
BEGIN
    SELECT (status = 'active') INTO group_active
    FROM groups WHERE group_id = p_group_id;

    IF NOT group_active THEN
        RETURN FALSE;
    END IF;

    SELECT is_banned INTO user_banned
    FROM users WHERE user_id = p_user_id;

    IF user_banned THEN
        RETURN FALSE;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM user_subscriptions 
        WHERE user_id = p_user_id 
          AND is_active = TRUE 
          AND expires_at > CURRENT_TIMESTAMP
    ) INTO user_has_subscription;

    RETURN user_has_subscription;
END;
$$;
ALTER FUNCTION public.can_user_execute_in_group(p_user_id bigint, p_group_id bigint, p_command_id integer) OWNER TO postgres;

CREATE FUNCTION public.cleanup_expired_cooldowns() RETURNS void
    LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM cooldowns WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$;
ALTER FUNCTION public.cleanup_expired_cooldowns() OWNER TO postgres;

CREATE FUNCTION public.create_subscription_key(p_admin_id bigint, p_plan_id integer, p_duration_days integer, p_bonus_credits integer DEFAULT 0, p_notes text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
AS $$
DECLARE
    admin_can_create BOOLEAN;
    new_key_code TEXT;
    expires_date TIMESTAMP;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM user_roles ur
        JOIN role_permissions rp ON ur.role = rp.role
        WHERE ur.user_id = p_admin_id
          AND rp.permission_name = 'can_create_keys'
          AND rp.is_allowed = TRUE
          AND ur.is_active = TRUE
    ) INTO admin_can_create;

    IF NOT admin_can_create THEN
        RETURN 'ERROR: Sin permisos para crear keys';
    END IF;

    new_key_code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CURRENT_TIMESTAMP::TEXT) FROM 1 FOR 12));
    expires_date := CURRENT_TIMESTAMP + (p_duration_days || ' days')::INTERVAL;

    INSERT INTO subscription_keys (
        key_code, plan_id, bonus_credits, created_by, expires_at, notes
    ) VALUES (
        new_key_code, p_plan_id, p_bonus_credits, p_admin_id, expires_date, p_notes
    );

    RETURN new_key_code;
END;
$$;
ALTER FUNCTION public.create_subscription_key(p_admin_id bigint, p_plan_id integer, p_duration_days integer, p_bonus_credits integer, p_notes text) OWNER TO postgres;

CREATE FUNCTION public.find_or_create_bank(p_name character varying) RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
  bank_id INTEGER;
BEGIN
  SELECT id INTO bank_id FROM banks WHERE name = p_name;

  IF bank_id IS NULL THEN
    INSERT INTO banks (name) VALUES (p_name) RETURNING id INTO bank_id;
  END IF;

  RETURN bank_id;
END;
$$;
ALTER FUNCTION public.find_or_create_bank(p_name character varying) OWNER TO postgres;

CREATE FUNCTION public.find_or_create_bin(p_bin character varying) RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
  bin_id INTEGER;
BEGIN
  SELECT id INTO bin_id FROM bins WHERE bin_number = p_bin;

  IF bin_id IS NULL THEN
    INSERT INTO bins (bin_number, metadata) VALUES (p_bin, '{}') RETURNING id INTO bin_id;
  END IF;

  RETURN bin_id;
END;
$$;
ALTER FUNCTION public.find_or_create_bin(p_bin character varying) OWNER TO postgres;

CREATE FUNCTION public.find_or_create_card_brand(p_name character varying) RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
  brand_id INTEGER;
BEGIN
  SELECT id INTO brand_id FROM card_brands WHERE name = p_name;

  IF brand_id IS NULL THEN
    INSERT INTO card_brands (name) VALUES (p_name) RETURNING id INTO brand_id;
  END IF;

  RETURN brand_id;
END;
$$;
ALTER FUNCTION public.find_or_create_card_brand(p_name character varying) OWNER TO postgres;

CREATE FUNCTION public.find_or_create_card_level(p_name character varying) RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
  level_id INTEGER;
BEGIN
  SELECT id INTO level_id FROM card_levels WHERE name = p_name;

  IF level_id IS NULL THEN
    INSERT INTO card_levels (name) VALUES (p_name) RETURNING id INTO level_id;
  END IF;

  RETURN level_id;
END;
$$;
ALTER FUNCTION public.find_or_create_card_level(p_name character varying) OWNER TO postgres;

CREATE FUNCTION public.get_command_config(p_command_name text, p_config_key text DEFAULT NULL::text) RETURNS TABLE(config_key text, config_value text, config_type text)
    LANGUAGE plpgsql
AS $$
BEGIN
    IF p_config_key IS NOT NULL THEN
        RETURN QUERY
        SELECT cc.config_key::TEXT, cc.config_value::TEXT, cc.config_type::TEXT
        FROM command_configs cc
        JOIN commands c ON cc.command_id = c.command_id
        WHERE c.command_name = p_command_name AND cc.config_key = p_config_key;
    ELSE
        RETURN QUERY
        SELECT cc.config_key::TEXT, cc.config_value::TEXT, cc.config_type::TEXT
        FROM command_configs cc
        JOIN commands c ON cc.command_id = c.command_id
        WHERE c.command_name = p_command_name;
    END IF;
END;
$$;
ALTER FUNCTION public.get_command_config(p_command_name text, p_config_key text) OWNER TO postgres;

CREATE FUNCTION public.get_user_max_plan_level(p_user_id bigint, p_context_type public.chat_type, p_context_chat_id bigint DEFAULT NULL::bigint) RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
    max_level INTEGER := 0;
BEGIN
    SELECT COALESCE(MAX(sp.plan_level), 0) INTO max_level
    FROM user_subscriptions us
    JOIN subscription_plans sp ON us.plan_id = sp.plan_id
    WHERE us.user_id = p_user_id
      AND us.context_type = p_context_type
      AND (p_context_chat_id IS NULL OR us.context_chat_id = p_context_chat_id)
      AND us.is_active = TRUE
      AND us.expires_at > CURRENT_TIMESTAMP;

    RETURN max_level;
END;
$$;
ALTER FUNCTION public.get_user_max_plan_level(p_user_id bigint, p_context_type public.chat_type, p_context_chat_id bigint) OWNER TO postgres;

CREATE FUNCTION public.give_credits_to_user(p_admin_id bigint, p_target_user_id bigint, p_credits_amount integer, p_reason text DEFAULT 'Créditos otorgados por admin'::text) RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    admin_can_manage BOOLEAN;
    current_credits INTEGER;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM user_roles ur
        JOIN role_permissions rp ON ur.role = rp.role
        WHERE ur.user_id = p_admin_id
          AND rp.permission_name = 'can_manage_credits'
          AND rp.is_allowed = TRUE
          AND ur.is_active = TRUE
    ) INTO admin_can_manage;

    IF NOT admin_can_manage THEN
        RETURN FALSE;
    END IF;

    SELECT COALESCE(available_credits, 0) INTO current_credits
    FROM user_credits WHERE user_id = p_target_user_id;

    INSERT INTO user_credits (user_id, total_credits, used_credits)
    VALUES (p_target_user_id, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    UPDATE user_credits 
    SET total_credits = total_credits + p_credits_amount
    WHERE user_id = p_target_user_id;

    INSERT INTO credit_transactions (
        user_id, transaction_type, amount, 
        previous_balance, new_balance, 
        description, created_by
    ) VALUES (
        p_target_user_id, 'manual_add', p_credits_amount,
        current_credits, current_credits + p_credits_amount,
        p_reason, p_admin_id
    );

    RETURN TRUE;
END;
$$;
ALTER FUNCTION public.give_credits_to_user(p_admin_id bigint, p_target_user_id bigint, p_credits_amount integer, p_reason text) OWNER TO postgres;

CREATE FUNCTION public.invalidate_old_cache() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.ip_address = NEW.ip_address THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        UPDATE scamalytics_cache 
        SET is_cache_valid = FALSE
        WHERE last_updated < NOW() - INTERVAL '3 days'
        AND is_cache_valid = TRUE
        AND ip_address != NEW.ip_address;
    END IF;

    RETURN NEW;
END;
$$;
ALTER FUNCTION public.invalidate_old_cache() OWNER TO postgres;

CREATE FUNCTION public.redeem_subscription_key(p_user_id bigint, p_key_code text) RETURNS text
    LANGUAGE plpgsql
AS $$
DECLARE
    key_data RECORD;
    current_credits INTEGER;
    new_expires_date TIMESTAMP;
BEGIN
    SELECT k.*, sp.duration_months, sp.credits_included, sp.plan_name
    INTO key_data
    FROM subscription_keys k
    JOIN subscription_plans sp ON k.plan_id = sp.plan_id
    WHERE k.key_code = p_key_code
      AND k.is_used = FALSE
      AND (k.expires_at IS NULL OR k.expires_at > CURRENT_TIMESTAMP);

    IF NOT FOUND THEN
        RETURN 'ERROR: Key inválida o expirada';
    END IF;

    new_expires_date := CURRENT_TIMESTAMP + (key_data.duration_months || ' months')::INTERVAL;

    UPDATE subscription_keys 
    SET is_used = TRUE, used_by = p_user_id, used_at = CURRENT_TIMESTAMP
    WHERE key_code = p_key_code;

    INSERT INTO user_subscriptions (user_id, plan_id, expires_at, key_used)
    VALUES (p_user_id, key_data.plan_id, new_expires_date, p_key_code)
    ON CONFLICT (user_id) 
    DO UPDATE SET 
        plan_id = EXCLUDED.plan_id,
        expires_at = EXCLUDED.expires_at,
        key_used = EXCLUDED.key_used,
        is_active = TRUE;

    SELECT COALESCE(available_credits, 0) INTO current_credits
    FROM user_credits WHERE user_id = p_user_id;

    INSERT INTO user_credits (user_id, total_credits, used_credits)
    VALUES (p_user_id, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    IF (key_data.credits_included + key_data.bonus_credits) > 0 THEN
        UPDATE user_credits 
        SET total_credits = total_credits + key_data.credits_included + key_data.bonus_credits
        WHERE user_id = p_user_id;

        IF key_data.credits_included > 0 THEN
            INSERT INTO credit_transactions (
                user_id, transaction_type, amount, 
                previous_balance, new_balance, 
                description, reference_id
            ) VALUES (
                p_user_id, 'bonus', key_data.credits_included,
                current_credits, current_credits + key_data.credits_included,
                'Créditos incluidos en plan ' || key_data.plan_name, p_key_code
            );
        END IF;

        IF key_data.bonus_credits > 0 THEN
            INSERT INTO credit_transactions (
                user_id, transaction_type, amount, 
                previous_balance, new_balance, 
                description, reference_id
            ) VALUES (
                p_user_id, 'bonus', key_data.bonus_credits,
                current_credits + key_data.credits_included, 
                current_credits + key_data.credits_included + key_data.bonus_credits,
                'Créditos bonus de key especial', p_key_code
            );
        END IF;
    END IF;

    RETURN 'SUCCESS: Suscripción activada correctamente';
END;
$$;
ALTER FUNCTION public.redeem_subscription_key(p_user_id bigint, p_key_code text) OWNER TO postgres;

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

CREATE FUNCTION public.update_user_ban_status() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE users 
        SET is_banned = EXISTS(
            SELECT 1 FROM user_bans 
            WHERE user_id = NEW.user_id 
              AND is_active = TRUE 
              AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        )
        WHERE user_id = NEW.user_id;

        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users 
        SET is_banned = EXISTS(
            SELECT 1 FROM user_bans 
            WHERE user_id = OLD.user_id 
              AND is_active = TRUE 
              AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        )
        WHERE user_id = OLD.user_id;

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;
ALTER FUNCTION public.update_user_ban_status() OWNER TO postgres;

CREATE FUNCTION public.update_user_statistics(p_user_id bigint) RETURNS void
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO user_statistics (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO UPDATE SET
        total_commands_executed = (
            SELECT COUNT(*) FROM command_executions WHERE user_id = p_user_id
        ),
        total_successful_commands = (
            SELECT COUNT(*) FROM command_executions WHERE user_id = p_user_id AND success = TRUE
        ),
        total_credits_spent = (
            SELECT COALESCE(SUM(credits_used), 0) FROM command_executions WHERE user_id = p_user_id
        ),
        last_updated = CURRENT_TIMESTAMP;
END;
$$;
ALTER FUNCTION public.update_user_statistics(p_user_id bigint) OWNER TO postgres;

CREATE FUNCTION public.user_can_access_command(p_user_id bigint, p_command_name text, p_context_type public.chat_type DEFAULT 'private'::public.chat_type, p_context_chat_id bigint DEFAULT NULL::bigint) RETURNS TABLE(can_access boolean, plan_level integer, base_cost integer, final_cost integer, cooldown_seconds integer, reason text)
    LANGUAGE plpgsql
AS $$
DECLARE
    cmd_data RECORD;
    user_plan_level INTEGER;
    access_data RECORD;
BEGIN
    SELECT c.*, cc.category_name
    INTO cmd_data
    FROM commands c
    JOIN command_categories cc ON c.category_id = cc.category_id
    WHERE c.command_name = p_command_name AND c.is_active = TRUE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 0, 0, 0, 0, 'Comando no encontrado o inactivo';
        RETURN;
    END IF;

    user_plan_level := get_user_max_plan_level(p_user_id, p_context_type, p_context_chat_id);

    IF user_plan_level < cmd_data.minimum_plan_level THEN
        RETURN QUERY SELECT FALSE, user_plan_level, cmd_data.base_cost, cmd_data.base_cost, 
                     cmd_data.default_cooldown_seconds, 'Plan insuficiente';
        RETURN;
    END IF;

    SELECT pca.cost_modifier, pca.cooldown_modifier, pca.is_allowed
    INTO access_data
    FROM user_subscriptions us
    JOIN plan_command_access pca ON us.plan_id = pca.plan_id
    WHERE us.user_id = p_user_id
      AND pca.command_id = cmd_data.command_id
      AND us.is_active = TRUE
      AND us.expires_at > CURRENT_TIMESTAMP
    ORDER BY us.plan_id DESC
    LIMIT 1;

    IF FOUND AND access_data.is_allowed THEN
        RETURN QUERY SELECT 
            TRUE,
            user_plan_level,
            cmd_data.base_cost,
            (cmd_data.base_cost * COALESCE(access_data.cost_modifier, 1.0))::INTEGER,
            (cmd_data.default_cooldown_seconds * COALESCE(access_data.cooldown_modifier, 1.0))::INTEGER,
            'Acceso permitido';
    ELSE
        RETURN QUERY SELECT FALSE, user_plan_level, cmd_data.base_cost, cmd_data.base_cost,
                     cmd_data.default_cooldown_seconds, 'Sin permisos en el plan actual';
    END IF;

    RETURN;
END;
$$;
ALTER FUNCTION public.user_can_access_command(p_user_id bigint, p_command_name text, p_context_type public.chat_type, p_context_chat_id bigint) OWNER TO postgres;

SET default_tablespace = '';
SET default_table_access_method = heap;

-- 5) Tablas (y Secuencias/DEFAULTs)
-- A partir de aquí se incluyen todas las tablas con sus secuencias y defaults.
-- (El contenido corresponde exactamente al dump original para asegurar reproducibilidad.)

-- Name: access_tokens
CREATE TABLE public.access_tokens (
    token_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    token_hash character varying(255) NOT NULL,
    token_type character varying(50) DEFAULT 'web_access'::character varying,
    permissions jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone,
    last_used_at timestamp without time zone,
    is_active boolean DEFAULT true,
    revoked_at timestamp without time zone,
    revoked_by bigint,
    user_agent text,
    ip_address inet
);
ALTER TABLE public.access_tokens OWNER TO postgres;

-- Name: alembic_version
CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);
ALTER TABLE public.alembic_version OWNER TO postgres;

-- Name: app_cards + sequence
CREATE TABLE public.app_cards (
    id integer NOT NULL,
    file_id integer,
    card_number text NOT NULL,
    exp_month text NOT NULL,
    exp_year text NOT NULL,
    cvv text NOT NULL,
    status text,
    gateway text,
    response text,
    bin_id integer,
    bank text,
    country text,
    card_info text,
    bin text,
    brand text,
    has_charge boolean DEFAULT false,
    response_has_charge boolean DEFAULT false,
    classification text DEFAULT 'Sin clasificar'::text,
    classified_date text,
    processed_date timestamp with time zone DEFAULT now() NOT NULL,
    gateway_cargo text
);
ALTER TABLE public.app_cards OWNER TO postgres;

CREATE SEQUENCE public.app_cards_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.app_cards_id_seq OWNER TO postgres;
ALTER SEQUENCE public.app_cards_id_seq OWNED BY public.app_cards.id;
ALTER TABLE ONLY public.app_cards ALTER COLUMN id SET DEFAULT nextval('public.app_cards_id_seq'::regclass);

-- Name: audit_log + sequence
CREATE TABLE public.audit_log (
    id integer NOT NULL,
    user_id integer,
    action character varying(20) NOT NULL,
    entity character varying(50) NOT NULL,
    entity_id character varying(100),
    "timestamp" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    details jsonb DEFAULT '{}'::jsonb,
    ip_address character varying(45)
);
ALTER TABLE public.audit_log OWNER TO postgres;

CREATE SEQUENCE public.audit_log_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.audit_log_id_seq OWNER TO postgres;
ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;
ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);

-- Name: banks + sequence
CREATE TABLE public.banks (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    website character varying(255),
    phone character varying(50),
    country_id integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.banks OWNER TO postgres;

CREATE SEQUENCE public.banks_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.banks_id_seq OWNER TO postgres;
ALTER SEQUENCE public.banks_id_seq OWNED BY public.banks.id;
ALTER TABLE ONLY public.banks ALTER COLUMN id SET DEFAULT nextval('public.banks_id_seq'::regclass);

-- Name: bins + sequence
CREATE TABLE public.bins (
    id integer NOT NULL,
    bin_number character varying(10) NOT NULL,
    brand_id integer,
    level_id integer,
    card_type character varying(20),
    country_id integer,
    bank_id integer,
    is_active boolean DEFAULT true NOT NULL,
    is_valid boolean DEFAULT false,
    has_country_info boolean DEFAULT false NOT NULL,
    has_bank_info boolean DEFAULT false NOT NULL,
    scraped_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.bins OWNER TO postgres;

CREATE SEQUENCE public.bins_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.bins_id_seq OWNER TO postgres;
ALTER SEQUENCE public.bins_id_seq OWNED BY public.bins.id;
ALTER TABLE ONLY public.bins ALTER COLUMN id SET DEFAULT nextval('public.bins_id_seq'::regclass);

-- Name: bot_settings + sequence
CREATE TABLE public.bot_settings (
    setting_id integer NOT NULL,
    setting_key character varying(100) NOT NULL,
    setting_value text,
    setting_type character varying(20) DEFAULT 'string'::character varying,
    category character varying(50) DEFAULT 'general'::character varying,
    description text,
    is_public boolean DEFAULT false,
    updated_by bigint,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.bot_settings OWNER TO postgres;

CREATE SEQUENCE public.bot_settings_setting_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.bot_settings_setting_id_seq OWNER TO postgres;
ALTER SEQUENCE public.bot_settings_setting_id_seq OWNED BY public.bot_settings.setting_id;
ALTER TABLE ONLY public.bot_settings ALTER COLUMN setting_id SET DEFAULT nextval('public.bot_settings_setting_id_seq'::regclass);

-- Name: card_brands + sequence
CREATE TABLE public.card_brands (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.card_brands OWNER TO postgres;

CREATE SEQUENCE public.card_brands_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.card_brands_id_seq OWNER TO postgres;
ALTER SEQUENCE public.card_brands_id_seq OWNED BY public.card_brands.id;
ALTER TABLE ONLY public.card_brands ALTER COLUMN id SET DEFAULT nextval('public.card_brands_id_seq'::regclass);

-- Name: card_levels + sequence
CREATE TABLE public.card_levels (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    brand_id integer,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.card_levels OWNER TO postgres;

CREATE SEQUENCE public.card_levels_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.card_levels_id_seq OWNER TO postgres;
ALTER SEQUENCE public.card_levels_id_seq OWNED BY public.card_levels.id;
ALTER TABLE ONLY public.card_levels ALTER COLUMN id SET DEFAULT nextval('public.card_levels_id_seq'::regclass);

-- Name: card_logs + sequence
CREATE TABLE public.card_logs (
    id integer NOT NULL,
    gateway character varying(100),
    gateway_type character varying(100),
    status character varying(50),
    card_number character varying(19),
    month character varying(2),
    year character varying(4),
    cvv character varying(4),
    response text,
    bin_id integer,
    card_brand_id integer,
    card_level_id integer,
    bank_id integer,
    card_id integer,
    country character varying(100),
    charged boolean DEFAULT false,
    charge_amount character varying(20),
    raw_text text,
    processed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    source_file character varying(255),
    bin character varying(10),
    brand character varying(50),
    level character varying(50),
    card_type character varying(50),
    bank character varying(255)
);
ALTER TABLE public.card_logs OWNER TO postgres;

CREATE SEQUENCE public.card_logs_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.card_logs_id_seq OWNER TO postgres;
ALTER SEQUENCE public.card_logs_id_seq OWNED BY public.card_logs.id;
ALTER TABLE ONLY public.card_logs ALTER COLUMN id SET DEFAULT nextval('public.card_logs_id_seq'::regclass);

-- Name: cards + sequence
CREATE TABLE public.cards (
    id integer NOT NULL,
    card_number character varying(19) NOT NULL,
    bin_id integer,
    brand_id integer,
    level_id integer,
    card_type character varying(20),
    card_length integer,
    country_id integer,
    bank_id integer,
    expiry_month integer,
    expiry_year integer,
    cvv_length integer DEFAULT 3,
    is_valid boolean,
    is_active boolean DEFAULT true NOT NULL,
    has_country_info boolean DEFAULT false NOT NULL,
    has_bank_info boolean DEFAULT false NOT NULL,
    verification_method character varying(50),
    last_validated timestamp with time zone,
    scraped_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.cards OWNER TO postgres;

CREATE SEQUENCE public.cards_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.cards_id_seq OWNER TO postgres;
ALTER SEQUENCE public.cards_id_seq OWNED BY public.cards.id;
ALTER TABLE ONLY public.cards ALTER COLUMN id SET DEFAULT nextval('public.cards_id_seq'::regclass);

-- Name: command_categories + sequence
CREATE TABLE public.command_categories (
    category_id integer NOT NULL,
    category_name character varying(50) NOT NULL,
    category_description text,
    display_order integer DEFAULT 0,
    is_active boolean DEFAULT true
);
ALTER TABLE public.command_categories OWNER TO postgres;

CREATE SEQUENCE public.command_categories_category_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.command_categories_category_id_seq OWNER TO postgres;
ALTER SEQUENCE public.command_categories_category_id_seq OWNED BY public.command_categories.category_id;
ALTER TABLE ONLY public.command_categories ALTER COLUMN category_id SET DEFAULT nextval('public.command_categories_category_id_seq'::regclass);

-- Name: command_configs
CREATE TABLE public.command_configs (
    config_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    command_id integer NOT NULL,
    config_key character varying(100) NOT NULL,
    config_value text NOT NULL,
    config_type character varying(20) DEFAULT 'string'::character varying,
    description text
);
ALTER TABLE public.command_configs OWNER TO postgres;

-- Name: command_executions (+ children inherited monthly)
CREATE TABLE public.command_executions (
    execution_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    command_id integer NOT NULL,
    chat_id bigint NOT NULL,
    chat_type public.chat_type NOT NULL,
    message_id integer,
    command_text text NOT NULL,
    arguments jsonb DEFAULT '{}'::jsonb,
    execution_result text,
    success boolean DEFAULT true,
    error_message text,
    credits_before integer,
    credits_used integer DEFAULT 0,
    credits_after integer,
    cost_breakdown jsonb DEFAULT '{}'::jsonb,
    execution_time_ms integer,
    started_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    completed_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb
);
ALTER TABLE public.command_executions OWNER TO postgres;

CREATE TABLE public.command_executions_2025_01 (
    CONSTRAINT command_executions_2025_01_started_at_check CHECK (((started_at >= '2025-01-01'::date) AND (started_at < '2025-02-01'::date)))
) INHERITS (public.command_executions);
ALTER TABLE public.command_executions_2025_01 OWNER TO postgres;

CREATE TABLE public.command_executions_2025_02 (
    CONSTRAINT command_executions_2025_02_started_at_check CHECK (((started_at >= '2025-02-01'::date) AND (started_at < '2025-03-01'::date)))
) INHERITS (public.command_executions);
ALTER TABLE public.command_executions_2025_02 OWNER TO postgres;

CREATE TABLE public.command_executions_2025_03 (
    CONSTRAINT command_executions_2025_03_started_at_check CHECK (((started_at >= '2025-03-01'::date) AND (started_at < '2025-04-01'::date)))
) INHERITS (public.command_executions);
ALTER TABLE public.command_executions_2025_03 OWNER TO postgres;

-- Name: command_statistics
CREATE TABLE public.command_statistics (
    command_id integer NOT NULL,
    total_executions integer DEFAULT 0,
    successful_executions integer DEFAULT 0,
    failed_executions integer DEFAULT 0,
    total_execution_time_ms bigint DEFAULT 0,
    avg_execution_time_ms integer DEFAULT 0,
    min_execution_time_ms integer DEFAULT 0,
    max_execution_time_ms integer DEFAULT 0,
    total_credits_consumed integer DEFAULT 0,
    avg_credits_per_execution numeric(10,2) DEFAULT 0,
    unique_users_count integer DEFAULT 0,
    most_active_user_id bigint,
    first_execution_at timestamp without time zone,
    last_execution_at timestamp without time zone,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.command_statistics OWNER TO postgres;

-- Name: commands + sequence
CREATE TABLE public.commands (
    command_id integer NOT NULL,
    command_name character varying(100) NOT NULL,
    command_description text,
    category_id integer NOT NULL,
    base_cost integer DEFAULT 0,
    minimum_credits_required integer DEFAULT 0,
    has_variable_cost boolean DEFAULT false,
    cost_calculation_method character varying(50),
    minimum_plan_level integer DEFAULT 1,
    requires_subscription boolean DEFAULT false,
    default_cooldown_seconds integer DEFAULT 0,
    is_active boolean DEFAULT true,
    is_beta boolean DEFAULT false,
    handler_class character varying(100),
    handler_method character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.commands OWNER TO postgres;

CREATE SEQUENCE public.commands_command_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.commands_command_id_seq OWNER TO postgres;
ALTER SEQUENCE public.commands_command_id_seq OWNED BY public.commands.command_id;
ALTER TABLE ONLY public.commands ALTER COLUMN command_id SET DEFAULT nextval('public.commands_command_id_seq'::regclass);

-- Name: cooldowns
CREATE TABLE public.cooldowns (
    cooldown_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    command_id integer NOT NULL,
    chat_id bigint NOT NULL,
    last_used timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    cooldown_seconds integer NOT NULL,
    expires_at timestamp without time zone NOT NULL
);
ALTER TABLE public.cooldowns OWNER TO postgres;

-- Name: countries + sequence
CREATE TABLE public.countries (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    code_a2 character(2),
    code_a3 character(3),
    currency character(3),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.countries OWNER TO postgres;

CREATE SEQUENCE public.countries_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.countries_id_seq OWNER TO postgres;
ALTER SEQUENCE public.countries_id_seq OWNED BY public.countries.id;
ALTER TABLE ONLY public.countries ALTER COLUMN id SET DEFAULT nextval('public.countries_id_seq'::regclass);

-- Name: credit_transactions
CREATE TABLE public.credit_transactions (
    transaction_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    transaction_type public.transaction_type NOT NULL,
    amount integer NOT NULL,
    previous_balance integer NOT NULL,
    new_balance integer NOT NULL,
    description text,
    reference_id character varying(100),
    command_execution_id uuid,
    created_by bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.credit_transactions OWNER TO postgres;

-- Name: daily_statistics
CREATE TABLE public.daily_statistics (
    stat_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    date date NOT NULL,
    new_users integer DEFAULT 0,
    active_users integer DEFAULT 0,
    users_with_commands integer DEFAULT 0,
    total_commands integer DEFAULT 0,
    successful_commands integer DEFAULT 0,
    failed_commands integer DEFAULT 0,
    unique_commands_used integer DEFAULT 0,
    credits_spent integer DEFAULT 0,
    credits_earned integer DEFAULT 0,
    credits_purchased integer DEFAULT 0,
    new_groups integer DEFAULT 0,
    active_groups integer DEFAULT 0,
    groups_activated integer DEFAULT 0,
    new_subscriptions integer DEFAULT 0,
    expired_subscriptions integer DEFAULT 0,
    keys_created integer DEFAULT 0,
    keys_used integer DEFAULT 0,
    avg_response_time_ms integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.daily_statistics OWNER TO postgres;

-- Name: global_statistics + sequence
CREATE TABLE public.global_statistics (
    stat_id integer NOT NULL,
    category character varying(50) NOT NULL,
    metric_name character varying(100) NOT NULL,
    metric_value bigint NOT NULL,
    calculation_date date DEFAULT CURRENT_DATE,
    description text,
    reference_table character varying(50),
    reference_query text
);
ALTER TABLE public.global_statistics OWNER TO postgres;

CREATE SEQUENCE public.global_statistics_stat_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.global_statistics_stat_id_seq OWNER TO postgres;
ALTER SEQUENCE public.global_statistics_stat_id_seq OWNED BY public.global_statistics.stat_id;
ALTER TABLE ONLY public.global_statistics ALTER COLUMN stat_id SET DEFAULT nextval('public.global_statistics_stat_id_seq'::regclass);

-- Name: groups
CREATE TABLE public.groups (
    group_id bigint NOT NULL,
    chat_type public.chat_type NOT NULL,
    title character varying(255),
    username character varying(32),
    description text,
    member_count integer DEFAULT 0,
    status public.group_status DEFAULT 'pending_activation'::public.group_status,
    activated_at timestamp without time zone,
    activated_by bigint,
    activation_notes text,
    max_daily_commands integer DEFAULT 100,
    requires_individual_subscription boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    added_by bigint
);
ALTER TABLE public.groups OWNER TO postgres;

-- Name: plan_command_access
CREATE TABLE public.plan_command_access (
    access_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    plan_id integer NOT NULL,
    command_id integer NOT NULL,
    is_allowed boolean DEFAULT true,
    cooldown_modifier numeric(3,2) DEFAULT 1.00,
    cost_modifier numeric(3,2) DEFAULT 1.00,
    daily_limit integer DEFAULT '-1'::integer,
    monthly_limit integer DEFAULT '-1'::integer
);
ALTER TABLE public.plan_command_access OWNER TO postgres;

-- Name: processed_files + sequence
CREATE TABLE public.processed_files (
    id integer NOT NULL,
    file_name character varying(255) NOT NULL,
    processed_date timestamp without time zone DEFAULT now(),
    cards_extracted integer DEFAULT 0
);
ALTER TABLE public.processed_files OWNER TO postgres;

CREATE SEQUENCE public.processed_files_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.processed_files_id_seq OWNER TO postgres;
ALTER SEQUENCE public.processed_files_id_seq OWNED BY public.processed_files.id;
ALTER TABLE ONLY public.processed_files ALTER COLUMN id SET DEFAULT nextval('public.processed_files_id_seq'::regclass);

-- Name: proxy_validations + sequence
CREATE TABLE public.proxy_validations (
    id integer NOT NULL,
    proxy_address character varying(255) NOT NULL,
    proxy_type character varying(50) NOT NULL,
    is_valid boolean NOT NULL,
    response_time integer,
    country character varying(100),
    city character varying(100),
    isp character varying(255),
    anonymity character varying(50),
    last_checked timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    source character varying(100),
    validation_method character varying(50)
);
ALTER TABLE public.proxy_validations OWNER TO postgres;

CREATE SEQUENCE public.proxy_validations_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.proxy_validations_id_seq OWNER TO postgres;
ALTER SEQUENCE public.proxy_validations_id_seq OWNED BY public.proxy_validations.id;
ALTER TABLE ONLY public.proxy_validations ALTER COLUMN id SET DEFAULT nextval('public.proxy_validations_id_seq'::regclass);

-- Name: role_permissions
CREATE TABLE public.role_permissions (
    permission_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    role public.admin_role NOT NULL,
    permission_name character varying(100) NOT NULL,
    is_allowed boolean DEFAULT true
);
ALTER TABLE public.role_permissions OWNER TO postgres;

-- Name: scamalytics_analysis + sequence
CREATE TABLE public.scamalytics_analysis (
    id integer NOT NULL,
    ip_address inet NOT NULL,
    fraud_score integer,
    risk_level character varying(20),
    hostname character varying(255),
    asn character varying(20),
    isp_name character varying(200),
    organization character varying(200),
    connection_type character varying(100),
    country_name character varying(100),
    country_code character varying(2),
    state_province character varying(100),
    district_county character varying(200),
    city character varying(100),
    postal_code character varying(20),
    latitude numeric(10,8),
    longitude numeric(11,8),
    is_datacenter boolean,
    is_blacklisted_firehol boolean,
    is_blacklisted_ip2proxy boolean,
    is_blacklisted_ipsum boolean,
    is_blacklisted_spamhaus boolean,
    is_blacklisted_x4bnet boolean,
    is_vpn boolean,
    is_tor boolean,
    is_server boolean,
    is_public_proxy boolean,
    is_web_proxy boolean,
    is_search_robot boolean,
    analysis_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    raw_html text
);
ALTER TABLE public.scamalytics_analysis OWNER TO postgres;

CREATE SEQUENCE public.scamalytics_analysis_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.scamalytics_analysis_id_seq OWNER TO postgres;
ALTER SEQUENCE public.scamalytics_analysis_id_seq OWNED BY public.scamalytics_analysis.id;
ALTER TABLE ONLY public.scamalytics_analysis ALTER COLUMN id SET DEFAULT nextval('public.scamalytics_analysis_id_seq'::regclass);

-- Name: scamalytics_cache + sequence
CREATE TABLE public.scamalytics_cache (
    id integer NOT NULL,
    ip_address inet NOT NULL,
    fraud_score integer,
    risk_level character varying(50),
    hostname character varying(255),
    asn character varying(20),
    isp_name character varying(200),
    organization character varying(200),
    connection_type character varying(100),
    country_name character varying(100),
    country_code character varying(2),
    state_province character varying(100),
    district_county character varying(200),
    city character varying(100),
    postal_code character varying(20),
    latitude numeric(10,8),
    longitude numeric(11,8),
    is_datacenter boolean,
    is_blacklisted_firehol boolean DEFAULT false,
    is_blacklisted_ip2proxy boolean DEFAULT false,
    is_blacklisted_ipsum boolean DEFAULT false,
    is_blacklisted_spamhaus boolean DEFAULT false,
    is_blacklisted_x4bnet boolean DEFAULT false,
    is_vpn boolean DEFAULT false,
    is_tor boolean DEFAULT false,
    is_server boolean DEFAULT false,
    is_public_proxy boolean DEFAULT false,
    is_web_proxy boolean DEFAULT false,
    is_search_robot boolean DEFAULT false,
    query_count integer DEFAULT 1,
    first_queried timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_scraped timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_cache_valid boolean DEFAULT true,
    raw_html text,
    notes text
);
ALTER TABLE public.scamalytics_cache OWNER TO postgres;

CREATE SEQUENCE public.scamalytics_cache_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.scamalytics_cache_id_seq OWNER TO postgres;
ALTER SEQUENCE public.scamalytics_cache_id_seq OWNED BY public.scamalytics_cache.id;
ALTER TABLE ONLY public.scamalytics_cache ALTER COLUMN id SET DEFAULT nextval('public.scamalytics_cache_id_seq'::regclass);

-- Name: scamalytics_query_log + sequence
CREATE TABLE public.scamalytics_query_log (
    id integer NOT NULL,
    ip_address inet NOT NULL,
    query_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    data_source character varying(20) DEFAULT 'cache'::character varying,
    fraud_score integer,
    risk_level character varying(50),
    query_duration_ms integer,
    user_agent text,
    session_id character varying(100)
);
ALTER TABLE public.scamalytics_query_log OWNER TO postgres;

CREATE SEQUENCE public.scamalytics_query_log_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.scamalytics_query_log_id_seq OWNER TO postgres;
ALTER SEQUENCE public.scamalytics_query_log_id_seq OWNED BY public.scamalytics_query_log.id;
ALTER TABLE ONLY public.scamalytics_query_log ALTER COLUMN id SET DEFAULT nextval('public.scamalytics_query_log_id_seq'::regclass);

-- Name: scraping_log + sequence
CREATE TABLE public.scraping_log (
    id integer NOT NULL,
    input_number character varying(10) NOT NULL,
    input_type character varying(50) NOT NULL,
    success boolean NOT NULL,
    has_valid_data boolean NOT NULL,
    response_time_ms integer,
    url_accessed text,
    error_message text,
    scraped_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.scraping_log OWNER TO postgres;

CREATE SEQUENCE public.scraping_log_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.scraping_log_id_seq OWNER TO postgres;
ALTER SEQUENCE public.scraping_log_id_seq OWNED BY public.scraping_log.id;
ALTER TABLE ONLY public.scraping_log ALTER COLUMN id SET DEFAULT nextval('public.scraping_log_id_seq'::regclass);

-- Name: search_log + sequence
CREATE TABLE public.search_log (
    id integer NOT NULL,
    user_id integer,
    search_type character varying(50) NOT NULL,
    search_term character varying(255) NOT NULL,
    result_count integer,
    "timestamp" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    details jsonb DEFAULT '{}'::jsonb,
    ip_address character varying(45)
);
ALTER TABLE public.search_log OWNER TO postgres;

CREATE SEQUENCE public.search_log_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.search_log_id_seq OWNER TO postgres;
ALTER SEQUENCE public.search_log_id_seq OWNED BY public.search_log.id;
ALTER TABLE ONLY public.search_log ALTER COLUMN id SET DEFAULT nextval('public.search_log_id_seq'::regclass);

-- Name: service_health_logs + sequence
CREATE TABLE public.service_health_logs (
    id integer NOT NULL,
    service_name character varying(100),
    status character varying(20),
    checked_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    response_time_ms integer,
    details text
);
ALTER TABLE public.service_health_logs OWNER TO postgres;

CREATE SEQUENCE public.service_health_logs_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.service_health_logs_id_seq OWNER TO postgres;
ALTER SEQUENCE public.service_health_logs_id_seq OWNED BY public.service_health_logs.id;
ALTER TABLE ONLY public.service_health_logs ALTER COLUMN id SET DEFAULT nextval('public.service_health_logs_id_seq'::regclass);

-- Name: subscription_keys
CREATE TABLE public.subscription_keys (
    key_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    key_code character varying(50) NOT NULL,
    plan_id integer NOT NULL,
    bonus_credits integer DEFAULT 0,
    created_by bigint NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone,
    is_used boolean DEFAULT false,
    used_by bigint,
    used_at timestamp without time zone,
    max_uses integer DEFAULT 1,
    current_uses integer DEFAULT 0,
    notes text
);
ALTER TABLE public.subscription_keys OWNER TO postgres;

-- Name: subscription_plans + sequence
CREATE TABLE public.subscription_plans (
    plan_id integer NOT NULL,
    plan_name character varying(100) NOT NULL,
    plan_description text,
    plan_level integer DEFAULT 1 NOT NULL,
    duration_months integer NOT NULL,
    price numeric(10,2) DEFAULT 0.00,
    currency character varying(3) DEFAULT 'USD'::character varying,
    credits_included integer DEFAULT 0,
    credits_monthly_bonus integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.subscription_plans OWNER TO postgres;

CREATE SEQUENCE public.subscription_plans_plan_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.subscription_plans_plan_id_seq OWNER TO postgres;
ALTER SEQUENCE public.subscription_plans_plan_id_seq OWNED BY public.subscription_plans.plan_id;
ALTER TABLE ONLY public.subscription_plans ALTER COLUMN plan_id SET DEFAULT nextval('public.subscription_plans_plan_id_seq'::regclass);

-- Name: system_errors + sequence
CREATE TABLE public.system_errors (
    id integer NOT NULL,
    error_type character varying(100),
    error_message text,
    occurred_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    context jsonb
);
ALTER TABLE public.system_errors OWNER TO postgres;

CREATE SEQUENCE public.system_errors_id_seq AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE public.system_errors_id_seq OWNER TO postgres;
ALTER SEQUENCE public.system_errors_id_seq OWNED BY public.system_errors.id;
ALTER TABLE ONLY public.system_errors ALTER COLUMN id SET DEFAULT nextval('public.system_errors_id_seq'::regclass);

-- Name: user_bans
CREATE TABLE public.user_bans (
    ban_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    ban_type public.ban_type NOT NULL,
    reason text NOT NULL,
    description text,
    banned_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    banned_by bigint NOT NULL,
    expires_at timestamp without time zone,
    is_active boolean DEFAULT true,
    unbanned_at timestamp without time zone,
    unbanned_by bigint,
    unban_reason text,
    context_type public.chat_type DEFAULT 'private'::public.chat_type,
    context_chat_id bigint
);
ALTER TABLE public.user_bans OWNER TO postgres;

-- Name: user_command_overrides
CREATE TABLE public.user_command_overrides (
    override_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    command_id integer NOT NULL,
    custom_cooldown_seconds integer,
    credit_multiplier numeric(3,2) DEFAULT 1.00,
    created_by bigint NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone,
    is_active boolean DEFAULT true,
    notes text
);
ALTER TABLE public.user_command_overrides OWNER TO postgres;

-- Name: user_credits
CREATE TABLE public.user_credits (
    user_id bigint NOT NULL,
    total_credits integer DEFAULT 0,
    used_credits integer DEFAULT 0,
    available_credits integer GENERATED ALWAYS AS ((total_credits - used_credits)) STORED,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.user_credits OWNER TO postgres;

-- Name: user_history
CREATE TABLE public.user_history (
    history_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    field_changed character varying(50) NOT NULL,
    old_value text,
    new_value text,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    change_source character varying(50) DEFAULT 'telegram'::character varying,
    notes text
);
ALTER TABLE public.user_history OWNER TO postgres;

-- Name: user_reports
CREATE TABLE public.user_reports (
    report_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    reported_user_id bigint NOT NULL,
    reporter_user_id bigint,
    report_reason character varying(100) NOT NULL,
    report_description text,
    report_type character varying(50) DEFAULT 'manual'::character varying,
    chat_id bigint,
    message_id integer,
    command_execution_id uuid,
    status public.report_status DEFAULT 'pending'::public.report_status,
    priority integer DEFAULT 1,
    reviewed_by bigint,
    reviewed_at timestamp without time zone,
    resolution_notes text,
    actions_taken jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.user_reports OWNER TO postgres;

-- Name: user_roles
CREATE TABLE public.user_roles (
    role_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    role public.admin_role NOT NULL,
    context_type public.chat_type DEFAULT 'private'::public.chat_type,
    context_chat_id bigint,
    granted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    granted_by bigint,
    expires_at timestamp without time zone,
    is_active boolean DEFAULT true,
    notes text
);
ALTER TABLE public.user_roles OWNER TO postgres;

-- Name: user_statistics
CREATE TABLE public.user_statistics (
    user_id bigint NOT NULL,
    total_commands_executed integer DEFAULT 0,
    total_successful_commands integer DEFAULT 0,
    total_failed_commands integer DEFAULT 0,
    total_credits_earned integer DEFAULT 0,
    total_credits_spent integer DEFAULT 0,
    total_credits_purchased integer DEFAULT 0,
    total_execution_time_ms bigint DEFAULT 0,
    avg_execution_time_ms integer DEFAULT 0,
    days_active integer DEFAULT 0,
    favorite_command character varying(100),
    most_used_chat_type public.chat_type,
    first_command_at timestamp without time zone,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.user_statistics OWNER TO postgres;

-- Name: user_subscriptions
CREATE TABLE public.user_subscriptions (
    subscription_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    plan_id integer NOT NULL,
    context_type public.chat_type DEFAULT 'private'::public.chat_type,
    activated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone NOT NULL,
    is_active boolean DEFAULT true,
    key_used character varying(50),
    activated_by bigint
);
ALTER TABLE public.user_subscriptions OWNER TO postgres;

-- Name: user_warnings
CREATE TABLE public.user_warnings (
    warning_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id bigint NOT NULL,
    warning_type public.warning_type NOT NULL,
    reason text NOT NULL,
    description text,
    severity integer DEFAULT 1,
    chat_id bigint,
    related_report_id uuid,
    related_command_execution_id uuid,
    issued_by bigint NOT NULL,
    issued_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone,
    is_active boolean DEFAULT true,
    acknowledged_by_user boolean DEFAULT false,
    acknowledged_at timestamp without time zone,
    admin_notes text
);
ALTER TABLE public.user_warnings OWNER TO postgres;

-- Name: users
CREATE TABLE public.users (
    user_id bigint NOT NULL,
    username character varying(32),
    first_name character varying(64) NOT NULL,
    last_name character varying(64),
    phone_number character varying(20),
    language_code character varying(10) DEFAULT 'es'::character varying,
    is_bot boolean DEFAULT false,
    is_premium boolean DEFAULT false,
    status public.user_status DEFAULT 'active'::public.user_status,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_activity timestamp without time zone,
    last_command_at timestamp without time zone,
    total_commands_used integer DEFAULT 0,
    total_credits_spent integer DEFAULT 0,
    is_banned boolean DEFAULT false
);
ALTER TABLE public.users OWNER TO postgres;

-- 10) Vistas
CREATE VIEW public.v_approved_cards AS
 SELECT cl.id,
    cl.gateway,
    cl.gateway_type,
    cl.status,
    cl.card_number,
    cl.month,
    cl.year,
    cl.cvv,
    cl.response,
    cl.bin_id,
    cl.card_brand_id,
    cl.card_level_id,
    cl.bank_id,
    cl.card_id,
    cl.country,
    cl.charged,
    cl.charge_amount,
    cl.raw_text,
    cl.processed,
    cl.created_at,
    b.bin_number,
    cb.name AS brand_name,
    cl2.name AS level_name,
    b2.name AS bank_name
   FROM ((((public.card_logs cl
     LEFT JOIN public.bins b ON ((cl.bin_id = b.id)))
     LEFT JOIN public.card_brands cb ON ((cl.card_brand_id = cb.id)))
     LEFT JOIN public.card_levels cl2 ON ((cl.card_level_id = cl2.id)))
     LEFT JOIN public.banks b2 ON ((cl.bank_id = b2.id)))
  WHERE ((cl.status)::text = 'Approved'::text);
ALTER VIEW public.v_approved_cards OWNER TO postgres;

CREATE VIEW public.v_charged_cards AS
 SELECT cl.id,
    cl.gateway,
    cl.gateway_type,
    cl.status,
    cl.card_number,
    cl.month,
    cl.year,
    cl.cvv,
    cl.response,
    cl.bin_id,
    cl.card_brand_id,
    cl.card_level_id,
    cl.bank_id,
    cl.card_id,
    cl.country,
    cl.charged,
    cl.charge_amount,
    cl.raw_text,
    cl.processed,
    cl.created_at,
    b.bin_number,
    cb.name AS brand_name,
    cl2.name AS level_name,
    b2.name AS bank_name
   FROM ((((public.card_logs cl
     LEFT JOIN public.bins b ON ((cl.bin_id = b.id)))
     LEFT JOIN public.card_brands cb ON ((cl.card_brand_id = cb.id)))
     LEFT JOIN public.card_levels cl2 ON ((cl.card_level_id = cl2.id)))
     LEFT JOIN public.banks b2 ON ((cl.bank_id = b2.id)))
  WHERE (cl.charged = true);
ALTER VIEW public.v_charged_cards OWNER TO postgres;

CREATE VIEW public.v_unprocessed_cards AS
 SELECT cl.id,
    cl.gateway,
    cl.gateway_type,
    cl.status,
    cl.card_number,
    cl.month,
    cl.year,
    cl.cvv,
    cl.response,
    cl.bin_id,
    cl.card_brand_id,
    cl.card_level_id,
    cl.bank_id,
    cl.card_id,
    cl.country,
    cl.charged,
    cl.charge_amount,
    cl.raw_text,
    cl.processed,
    cl.created_at,
    b.bin_number,
    cb.name AS brand_name,
    cl2.name AS level_name,
    b2.name AS bank_name
   FROM ((((public.card_logs cl
     LEFT JOIN public.bins b ON ((cl.bin_id = b.id)))
     LEFT JOIN public.card_brands cb ON ((cl.card_brand_id = cb.id)))
     LEFT JOIN public.card_levels cl2 ON ((cl.card_level_id = cl2.id)))
     LEFT JOIN public.banks b2 ON ((cl.bank_id = b2.id)))
  WHERE (cl.processed = false);
ALTER VIEW public.v_unprocessed_cards OWNER TO postgres;

-- 6) Constraints (PK/UK)
-- (Sección completa trasladada intacta para mantener consistencia con el dump)
ALTER TABLE ONLY public.access_tokens ADD CONSTRAINT access_tokens_pkey PRIMARY KEY (token_id);
ALTER TABLE ONLY public.access_tokens ADD CONSTRAINT access_tokens_token_hash_key UNIQUE (token_hash);
ALTER TABLE ONLY public.alembic_version ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);
ALTER TABLE ONLY public.app_cards ADD CONSTRAINT app_cards_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.banks ADD CONSTRAINT banks_name_key UNIQUE (name);
ALTER TABLE ONLY public.banks ADD CONSTRAINT banks_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.bins ADD CONSTRAINT bins_bin_number_key UNIQUE (bin_number);
ALTER TABLE ONLY public.bins ADD CONSTRAINT bins_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.bot_settings ADD CONSTRAINT bot_settings_pkey PRIMARY KEY (setting_id);
ALTER TABLE ONLY public.bot_settings ADD CONSTRAINT bot_settings_setting_key_key UNIQUE (setting_key);
ALTER TABLE ONLY public.card_brands ADD CONSTRAINT card_brands_name_key UNIQUE (name);
ALTER TABLE ONLY public.card_brands ADD CONSTRAINT card_brands_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.card_levels ADD CONSTRAINT card_levels_name_brand_id_key UNIQUE (name, brand_id);
ALTER TABLE ONLY public.card_levels ADD CONSTRAINT card_levels_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.card_logs ADD CONSTRAINT card_logs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.cards ADD CONSTRAINT cards_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.command_categories ADD CONSTRAINT command_categories_category_name_key UNIQUE (category_name);
ALTER TABLE ONLY public.command_categories ADD CONSTRAINT command_categories_pkey PRIMARY KEY (category_id);
ALTER TABLE ONLY public.command_configs ADD CONSTRAINT command_configs_command_id_config_key_key UNIQUE (command_id, config_key);
ALTER TABLE ONLY public.command_configs ADD CONSTRAINT command_configs_pkey PRIMARY KEY (config_id);
ALTER TABLE ONLY public.command_executions ADD CONSTRAINT command_executions_pkey PRIMARY KEY (execution_id);
ALTER TABLE ONLY public.command_statistics ADD CONSTRAINT command_statistics_pkey PRIMARY KEY (command_id);
ALTER TABLE ONLY public.commands ADD CONSTRAINT commands_command_name_key UNIQUE (command_name);
ALTER TABLE ONLY public.commands ADD CONSTRAINT commands_pkey PRIMARY KEY (command_id);
ALTER TABLE ONLY public.cooldowns ADD CONSTRAINT cooldowns_pkey PRIMARY KEY (cooldown_id);
ALTER TABLE ONLY public.cooldowns ADD CONSTRAINT cooldowns_user_id_command_id_chat_id_key UNIQUE (user_id, command_id, chat_id);
ALTER TABLE ONLY public.countries ADD CONSTRAINT countries_code_a2_key UNIQUE (code_a2);
ALTER TABLE ONLY public.countries ADD CONSTRAINT countries_code_a3_key UNIQUE (code_a3);
ALTER TABLE ONLY public.countries ADD CONSTRAINT countries_name_key UNIQUE (name);
ALTER TABLE ONLY public.countries ADD CONSTRAINT countries_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.credit_transactions ADD CONSTRAINT credit_transactions_pkey PRIMARY KEY (transaction_id);
ALTER TABLE ONLY public.daily_statistics ADD CONSTRAINT daily_statistics_date_key UNIQUE (date);
ALTER TABLE ONLY public.daily_statistics ADD CONSTRAINT daily_statistics_pkey PRIMARY KEY (stat_id);
ALTER TABLE ONLY public.global_statistics ADD CONSTRAINT global_statistics_category_metric_name_calculation_date_key UNIQUE (category, metric_name, calculation_date);
ALTER TABLE ONLY public.global_statistics ADD CONSTRAINT global_statistics_pkey PRIMARY KEY (stat_id);
ALTER TABLE ONLY public.groups ADD CONSTRAINT groups_pkey PRIMARY KEY (group_id);
ALTER TABLE ONLY public.plan_command_access ADD CONSTRAINT plan_command_access_pkey PRIMARY KEY (access_id);
ALTER TABLE ONLY public.plan_command_access ADD CONSTRAINT plan_command_access_plan_id_command_id_key UNIQUE (plan_id, command_id);
ALTER TABLE ONLY public.processed_files ADD CONSTRAINT processed_files_file_name_key UNIQUE (file_name);
ALTER TABLE ONLY public.processed_files ADD CONSTRAINT processed_files_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (permission_id);
ALTER TABLE ONLY public.role_permissions ADD CONSTRAINT role_permissions_role_permission_name_key UNIQUE (role, permission_name);
ALTER TABLE ONLY public.scamalytics_analysis ADD CONSTRAINT scamalytics_analysis_ip_address_key UNIQUE (ip_address);
ALTER TABLE ONLY public.scamalytics_analysis ADD CONSTRAINT scamalytics_analysis_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.scamalytics_cache ADD CONSTRAINT scamalytics_cache_ip_address_key UNIQUE (ip_address);
ALTER TABLE ONLY public.scamalytics_cache ADD CONSTRAINT scamalytics_cache_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.scamalytics_query_log ADD CONSTRAINT scamalytics_query_log_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.scraping_log ADD CONSTRAINT scraping_log_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.service_health_logs ADD CONSTRAINT service_health_logs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.subscription_keys ADD CONSTRAINT subscription_keys_key_code_key UNIQUE (key_code);
ALTER TABLE ONLY public.subscription_keys ADD CONSTRAINT subscription_keys_pkey PRIMARY KEY (key_id);
ALTER TABLE ONLY public.subscription_plans ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (plan_id);
ALTER TABLE ONLY public.subscription_plans ADD CONSTRAINT subscription_plans_plan_name_key UNIQUE (plan_name);
ALTER TABLE ONLY public.system_errors ADD CONSTRAINT system_errors_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.user_bans ADD CONSTRAINT user_bans_pkey PRIMARY KEY (ban_id);
ALTER TABLE ONLY public.user_command_overrides ADD CONSTRAINT user_command_overrides_pkey PRIMARY KEY (override_id);
ALTER TABLE ONLY public.user_command_overrides ADD CONSTRAINT user_command_overrides_user_id_command_id_key UNIQUE (user_id, command_id);
ALTER TABLE ONLY public.user_credits ADD CONSTRAINT user_credits_pkey PRIMARY KEY (user_id);
ALTER TABLE ONLY public.user_history ADD CONSTRAINT user_history_pkey PRIMARY KEY (history_id);
ALTER TABLE ONLY public.user_reports ADD CONSTRAINT user_reports_pkey PRIMARY KEY (report_id);
ALTER TABLE ONLY public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (role_id);
ALTER TABLE ONLY public.user_statistics ADD CONSTRAINT user_statistics_pkey PRIMARY KEY (user_id);
ALTER TABLE ONLY public.user_subscriptions ADD CONSTRAINT user_subscriptions_pkey PRIMARY KEY (subscription_id);
ALTER TABLE ONLY public.user_subscriptions ADD CONSTRAINT user_subscriptions_user_id_key UNIQUE (user_id);
ALTER TABLE ONLY public.user_warnings ADD CONSTRAINT user_warnings_pkey PRIMARY KEY (warning_id);
ALTER TABLE ONLY public.users ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);
ALTER TABLE ONLY public.webhook_logs ADD CONSTRAINT webhook_logs_pkey PRIMARY KEY (id);

-- 7) Índices
-- (Se conservan exactamente como en el dump original)
CREATE INDEX idx_access_tokens_expires ON public.access_tokens USING btree (expires_at);
CREATE INDEX idx_access_tokens_user ON public.access_tokens USING btree (user_id);
CREATE INDEX idx_app_cards_card_number ON public.app_cards USING btree (card_number);
CREATE INDEX idx_banks_name ON public.banks USING btree (name);
CREATE INDEX idx_bins_bank_active ON public.bins USING btree (bank_id, is_active);
CREATE INDEX idx_bins_bin_number ON public.bins USING btree (bin_number);
CREATE INDEX idx_bins_country_brand ON public.bins USING btree (country_id, brand_id);
CREATE INDEX idx_bins_scraped_date ON public.bins USING btree (scraped_at);
CREATE INDEX idx_bot_settings_category ON public.bot_settings USING btree (category);
CREATE INDEX idx_card_brands_name ON public.card_brands USING btree (name);
CREATE INDEX idx_card_logs_bin_id ON public.card_logs USING btree (bin_id);
CREATE INDEX idx_card_logs_charged ON public.card_logs USING btree (charged);
CREATE INDEX idx_card_logs_gateway ON public.card_logs USING btree (gateway);
CREATE INDEX idx_card_logs_processed ON public.card_logs USING btree (processed);
CREATE INDEX idx_card_logs_status ON public.card_logs USING btree (status);
CREATE INDEX idx_cards_card_number ON public.cards USING btree (card_number);
CREATE INDEX idx_command_executions_chat ON public.command_executions USING btree (chat_id, started_at);
CREATE INDEX idx_command_executions_command ON public.command_executions USING btree (command_id);
CREATE INDEX idx_command_executions_user_command_date ON public.command_executions USING btree (user_id, command_id, started_at);
CREATE INDEX idx_command_executions_user_date ON public.command_executions USING btree (user_id, started_at);
CREATE INDEX idx_command_stats_executions ON public.command_statistics USING btree (total_executions);
CREATE INDEX idx_command_stats_performance ON public.command_statistics USING btree (avg_execution_time_ms);
CREATE INDEX idx_commands_active ON public.commands USING btree (is_active);
CREATE INDEX idx_commands_category ON public.commands USING btree (category_id);
CREATE INDEX idx_cooldowns_expires ON public.cooldowns USING btree (expires_at);
CREATE INDEX idx_cooldowns_user_command ON public.cooldowns USING btree (user_id, command_id);
CREATE INDEX idx_countries_name ON public.countries USING btree (name);
CREATE INDEX idx_credit_transactions_type ON public.credit_transactions USING btree (transaction_type);
CREATE INDEX idx_credit_transactions_user_date ON public.credit_transactions USING btree (user_id, created_at);
CREATE INDEX idx_daily_stats_date ON public.daily_statistics USING btree (date);
CREATE INDEX idx_global_stats_category ON public.global_statistics USING btree (category);
CREATE INDEX idx_global_stats_date ON public.global_statistics USING btree (calculation_date);
CREATE INDEX idx_groups_status ON public.groups USING btree (status);
CREATE INDEX idx_groups_type ON public.groups USING btree (chat_type);
CREATE INDEX idx_keys_code ON public.subscription_keys USING btree (key_code);
CREATE INDEX idx_keys_expires ON public.subscription_keys USING btree (expires_at);
CREATE INDEX idx_plans_active ON public.subscription_plans USING btree (is_active);
CREATE INDEX idx_plans_level ON public.subscription_plans USING btree (plan_level);
CREATE INDEX idx_reports_priority ON public.user_reports USING btree (priority);
CREATE INDEX idx_reports_reported_user ON public.user_reports USING btree (reported_user_id);
CREATE INDEX idx_reports_status ON public.user_reports USING btree (status);
CREATE INDEX idx_scam_cache_score ON public.scamalytics_cache USING btree (fraud_score);
CREATE INDEX idx_scam_cache_updated ON public.scamalytics_cache USING btree (last_updated);
CREATE INDEX idx_scam_cache_valid ON public.scamalytics_cache USING btree (is_cache_valid);
CREATE INDEX idx_scam_ip ON public.scamalytics_analysis USING btree (ip_address);
CREATE INDEX idx_scam_log_ip ON public.scamalytics_query_log USING btree (ip_address);
CREATE INDEX idx_scam_log_timestamp ON public.scamalytics_query_log USING btree (query_timestamp);
CREATE INDEX idx_scam_risk ON public.scamalytics_analysis USING btree (risk_level);
CREATE INDEX idx_scam_score ON public.scamalytics_analysis USING btree (fraud_score);
CREATE INDEX idx_scamalytics_cache_is_valid ON public.scamalytics_cache USING btree (is_cache_valid);
CREATE INDEX idx_scamalytics_cache_last_updated ON public.scamalytics_cache USING btree (last_updated);
CREATE INDEX idx_scraping_log_input_number ON public.scraping_log USING btree (input_number);
CREATE INDEX idx_scraping_log_success_date ON public.scraping_log USING btree (success, scraped_at);
CREATE INDEX idx_scraping_log_type_date ON public.scraping_log USING btree (input_type, scraped_at);
CREATE INDEX idx_subscriptions_active ON public.user_subscriptions USING btree (is_active);
CREATE INDEX idx_subscriptions_expires ON public.user_subscriptions USING btree (expires_at);
CREATE INDEX idx_user_bans_active ON public.user_bans USING btree (is_active);
CREATE INDEX idx_user_bans_expires ON public.user_bans USING btree (expires_at);
CREATE INDEX idx_user_bans_user ON public.user_bans USING btree (user_id);
CREATE INDEX idx_user_history_field ON public.user_history USING btree (field_changed);
CREATE INDEX idx_user_history_user_date ON public.user_history USING btree (user_id, changed_at);
CREATE INDEX idx_user_roles_context ON public.user_roles USING btree (context_type, context_chat_id);
CREATE INDEX idx_user_roles_user ON public.user_roles USING btree (user_id);
CREATE INDEX idx_user_stats_commands ON public.user_statistics USING btree (total_commands_executed);
CREATE INDEX idx_user_stats_credits ON public.user_statistics USING btree (total_credits_spent);
CREATE INDEX idx_user_subscriptions_active_expires ON public.user_subscriptions USING btree (is_active, expires_at);
CREATE INDEX idx_users_is_banned ON public.users USING btree (is_banned);
CREATE INDEX idx_users_last_activity ON public.users USING btree (last_activity);
CREATE INDEX idx_users_status ON public.users USING btree (status);
CREATE INDEX idx_users_username ON public.users USING btree (username);
CREATE INDEX idx_warnings_active ON public.user_warnings USING btree (is_active);
CREATE INDEX idx_warnings_severity ON public.user_warnings USING btree (severity);
CREATE INDEX idx_warnings_user ON public.user_warnings USING btree (user_id);

-- 8) Triggers
CREATE TRIGGER audit_access_tokens_crud AFTER INSERT OR DELETE OR UPDATE ON public.access_tokens FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_app_cards_crud AFTER INSERT OR DELETE OR UPDATE ON public.app_cards FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_banks_crud AFTER INSERT OR DELETE OR UPDATE ON public.banks FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_bins_crud AFTER INSERT OR DELETE OR UPDATE ON public.bins FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_bot_settings_crud AFTER INSERT OR DELETE OR UPDATE ON public.bot_settings FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_card_brands_crud AFTER INSERT OR DELETE OR UPDATE ON public.card_brands FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_card_levels_crud AFTER INSERT OR DELETE OR UPDATE ON public.card_levels FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_cards_crud AFTER INSERT OR DELETE OR UPDATE ON public.cards FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_command_categories_crud AFTER INSERT OR DELETE OR UPDATE ON public.command_categories FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_command_configs_crud AFTER INSERT OR DELETE OR UPDATE ON public.command_configs FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_command_executions_crud AFTER INSERT OR DELETE OR UPDATE ON public.command_executions FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_command_statistics_crud AFTER INSERT OR DELETE OR UPDATE ON public.command_statistics FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_commands_crud AFTER INSERT OR DELETE OR UPDATE ON public.commands FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_cooldowns_crud AFTER INSERT OR DELETE OR UPDATE ON public.cooldowns FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_countries_crud AFTER INSERT OR DELETE OR UPDATE ON public.countries FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_credit_transactions_crud AFTER INSERT OR DELETE OR UPDATE ON public.credit_transactions FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_daily_statistics_crud AFTER INSERT OR DELETE OR UPDATE ON public.daily_statistics FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_global_statistics_crud AFTER INSERT OR DELETE OR UPDATE ON public.global_statistics FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_groups_crud AFTER INSERT OR DELETE OR UPDATE ON public.groups FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_plan_command_access_crud AFTER INSERT OR DELETE OR UPDATE ON public.plan_command_access FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_role_permissions_crud AFTER INSERT OR DELETE OR UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_scamalytics_analysis_crud AFTER INSERT OR DELETE OR UPDATE ON public.scamalytics_analysis FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_scamalytics_cache_crud AFTER INSERT OR DELETE OR UPDATE ON public.scamalytics_cache FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_scamalytics_query_log_crud AFTER INSERT OR DELETE OR UPDATE ON public.scamalytics_query_log FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_scraping_log_crud AFTER INSERT OR DELETE OR UPDATE ON public.scraping_log FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_service_health_logs_crud AFTER INSERT OR DELETE OR UPDATE ON public.service_health_logs FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_subscription_keys_crud AFTER INSERT OR DELETE OR UPDATE ON public.subscription_keys FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_subscription_plans_crud AFTER INSERT OR DELETE OR UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_system_errors_crud AFTER INSERT OR DELETE OR UPDATE ON public.system_errors FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_bans_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_bans FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_command_overrides_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_command_overrides FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_credits_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_credits FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_history_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_history FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_reports_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_reports FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_roles_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_statistics_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_statistics FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_subscriptions_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_subscriptions FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_user_warnings_crud AFTER INSERT OR DELETE OR UPDATE ON public.user_warnings FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_users_crud AFTER INSERT OR DELETE OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();
CREATE TRIGGER audit_webhook_logs_crud AFTER INSERT OR DELETE OR UPDATE ON public.webhook_logs FOR EACH ROW EXECUTE FUNCTION public.audit_generic_crud_fn();

CREATE TRIGGER invalidate_old_cache_trigger AFTER INSERT OR UPDATE ON public.scamalytics_cache FOR EACH ROW EXECUTE FUNCTION public.invalidate_old_cache();
CREATE TRIGGER trigger_update_user_ban_status AFTER INSERT OR DELETE OR UPDATE ON public.user_bans FOR EACH ROW EXECUTE FUNCTION public.update_user_ban_status();
CREATE TRIGGER update_groups_updated_at BEFORE UPDATE ON public.groups FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 9) Claves Foráneas (FK)
ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.app_cards
    ADD CONSTRAINT app_cards_bin_id_fkey FOREIGN KEY (bin_id) REFERENCES public.bins(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.banks
    ADD CONSTRAINT banks_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.card_brands(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.card_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.bot_settings
    ADD CONSTRAINT bot_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.card_levels
    ADD CONSTRAINT card_levels_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.card_brands(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.card_logs
    ADD CONSTRAINT card_logs_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id);
ALTER TABLE ONLY public.card_logs
    ADD CONSTRAINT card_logs_bin_id_fkey FOREIGN KEY (bin_id) REFERENCES public.bins(id);
ALTER TABLE ONLY public.card_logs
    ADD CONSTRAINT card_logs_card_brand_id_fkey FOREIGN KEY (card_brand_id) REFERENCES public.card_brands(id);
ALTER TABLE ONLY public.card_logs
    ADD CONSTRAINT card_logs_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.cards(id);
ALTER TABLE ONLY public.card_logs
    ADD CONSTRAINT card_logs_card_level_id_fkey FOREIGN KEY (card_level_id) REFERENCES public.card_levels(id);

ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES public.banks(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_bin_id_fkey FOREIGN KEY (bin_id) REFERENCES public.bins(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.card_brands(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.cards
    ADD CONSTRAINT cards_level_id_fkey FOREIGN KEY (level_id) REFERENCES public.card_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.command_configs
    ADD CONSTRAINT command_configs_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.command_executions
    ADD CONSTRAINT command_executions_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id);
ALTER TABLE ONLY public.command_executions
    ADD CONSTRAINT command_executions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.command_statistics
    ADD CONSTRAINT command_statistics_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.command_statistics
    ADD CONSTRAINT command_statistics_most_active_user_id_fkey FOREIGN KEY (most_active_user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.commands
    ADD CONSTRAINT commands_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.command_categories(category_id);
ALTER TABLE ONLY public.commands
    ADD CONSTRAINT fk_commands_category_id FOREIGN KEY (category_id) REFERENCES public.command_categories(category_id) ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY public.cooldowns
    ADD CONSTRAINT cooldowns_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id);
ALTER TABLE ONLY public.cooldowns
    ADD CONSTRAINT cooldowns_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.credit_transactions
    ADD CONSTRAINT credit_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.credit_transactions
    ADD CONSTRAINT credit_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_activated_by_fkey FOREIGN KEY (activated_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.plan_command_access
    ADD CONSTRAINT plan_command_access_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id);
ALTER TABLE ONLY public.plan_command_access
    ADD CONSTRAINT plan_command_access_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(plan_id);

ALTER TABLE ONLY public.subscription_keys
    ADD CONSTRAINT subscription_keys_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.subscription_keys
    ADD CONSTRAINT subscription_keys_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(plan_id);
ALTER TABLE ONLY public.subscription_keys
    ADD CONSTRAINT subscription_keys_used_by_fkey FOREIGN KEY (used_by) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_banned_by_fkey FOREIGN KEY (banned_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_unbanned_by_fkey FOREIGN KEY (unbanned_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_command_overrides
    ADD CONSTRAINT user_command_overrides_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.commands(command_id);
ALTER TABLE ONLY public.user_command_overrides
    ADD CONSTRAINT user_command_overrides_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_command_overrides
    ADD CONSTRAINT user_command_overrides_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_credits
    ADD CONSTRAINT user_credits_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_history
    ADD CONSTRAINT user_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_command_execution_id_fkey FOREIGN KEY (command_execution_id) REFERENCES public.command_executions(execution_id);
ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reported_user_id_fkey FOREIGN KEY (reported_user_id) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reporter_user_id_fkey FOREIGN KEY (reporter_user_id) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_context_chat_id_fkey FOREIGN KEY (context_chat_id) REFERENCES public.groups(group_id);
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_statistics
    ADD CONSTRAINT user_statistics_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_subscriptions
    ADD CONSTRAINT user_subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(plan_id);
ALTER TABLE ONLY public.user_subscriptions
    ADD CONSTRAINT user_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

ALTER TABLE ONLY public.user_warnings
    ADD CONSTRAINT user_warnings_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.users(user_id);
ALTER TABLE ONLY public.user_warnings
    ADD CONSTRAINT user_warnings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);

-- 11) Grants/ACL
GRANT ALL ON SCHEMA public TO "AdminP0";

-- Completed on 2025-08-29 00:10:53
-- PostgreSQL database dump complete