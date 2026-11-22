-- Berikan hak akses penuh schema public, tabel, view, sequence, dan fungsi untuk service_role (Backend API)
-- Jalankan 1x di Supabase SQL Editor bila muncul error "permission denied for table ... / view ... (role service_role)".

grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, service_role;
grant all privileges on all sequences in schema public to postgres, service_role;
grant all privileges on all functions in schema public to postgres, service_role;
grant select on all tables in schema public to authenticated;

alter default privileges in schema public grant all on tables to postgres, service_role;
alter default privileges in schema public grant all on sequences to postgres, service_role;
alter default privileges in schema public grant all on functions to postgres, service_role;
