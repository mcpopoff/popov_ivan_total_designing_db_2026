do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'inspector') then
    create role inspector with login password 'NetoSQL2025';
  else
    alter role inspector with login password 'NetoSQL2025';
  end if;
end $$;

grant connect on database foodexpress to inspector;

-- права на схему popov_food
grant all privileges on schema popov_food to inspector;
grant all privileges on all tables in schema popov_food to inspector;
grant all privileges on all sequences in schema popov_food to inspector;
grant all privileges on all routines in schema popov_food to inspector;

-- дефолтные права для будущих объектов в схеме popov_food
alter default privileges in schema popov_food grant all on tables to inspector;
alter default privileges in schema popov_food grant all on sequences to inspector;
alter default privileges in schema popov_food grant all on routines to inspector;

-- права на схему exts для генерации uuid
grant usage on schema exts to inspector;
grant execute on all routines in schema exts to inspector;

-- права на системные схемы
grant usage on schema information_schema to inspector;
grant usage on schema pg_catalog to inspector;

-- настройки подключения
alter role inspector set search_path to popov_food, exts, public;
