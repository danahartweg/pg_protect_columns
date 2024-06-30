-- Ensure this can only be called via `create extension`.
\echo Use "CREATE EXTENSION pg_protect_columns" to load this file.
quit
/**
 * A procedure that returns a trigger that will ensure *any* provided column cannot be changed by an update update.
 * In general, you should prefix your trigger with an underscore to ensure it runs first.
 *
 * Returns:
 * - `trigger` - A trigger
 *
 * Throws:
 * - `restrict_violation` - If the column value has changed
 *
 * Example:
 * ```sql
 *   create trigger _protect_columns_before_update
 *     before update on table for each row
 *     execute procedure protect_columns('column_1', 'column_2');
 * ```
 */
create or replace function protect_columns()
	returns trigger
	as $$
declare
	target_columns text[] := TG_ARGV::text[];
	current_column text;
	new_value text;
	old_value text;
begin
	for i in array_lower(target_columns, 1)..array_upper(target_columns, 1)
	loop
		current_column := target_columns[i];
		-- Get current values from the new and old records for comparison.
		execute format('SELECT ($1).%I, ($2).%I', current_column, current_column) into new_value,
		old_value
		using new, old;
		-- If the column value has changed, disallow.
		if new_value is distinct from old_value then
			raise exception 'Modifying "%" is not allowed', current_column
				-- restrict_violation
				using errcode = '23001';
			end if;
		end loop;
		return new;
end;
$$
language plpgsql
strict stable;
