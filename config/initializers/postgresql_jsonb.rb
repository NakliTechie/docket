# The portable Ruby schema uses `t.json` because SQLite has no `jsonb` type.
# In PostgreSQL, make that portable declaration create jsonb so a schema load
# has the same production-safe types as a full migration replay.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  native_types = const_get(:NATIVE_DATABASE_TYPES)
  native_types[:json] = native_types.fetch(:jsonb).dup
end
