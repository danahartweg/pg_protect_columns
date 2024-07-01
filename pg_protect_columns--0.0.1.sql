-- Ensure this can only be called via `create extension`.
\echo Use "CREATE EXTENSION pg_protect_columns" to load this file. \quit
/**
 * A function that returns a trigger to be used as a procedure that will ensure *any* designated columns
 * cannot be changed by the specified action (usually update).
 * In general, you should prefix your trigger with an underscore to ensure it runs first.
 *
 * Returns:
 * - `trigger` - A trigger to protect the designated columns.
 *
 * Throws:
 * - `restrict_violation` - If the column value has changed.
 *
 * Example:
 * ```sql
 *   create trigger _protect_columns_before_update
 *     before update on table for each row
 *     execute procedure protect_columns('column_1', 'column_2');
 * ```
 */
create or replace function @extschema@.protect_columns()
	returns trigger
	as $$
declare
	target_columns text[] := TG_ARGV::text[];
	current_column text;
	new_value text;
	old_value text;
	disabled_column text := coalesce(current_setting('pg_protect_columns.disable_protection_on_column'::text, true), '');
begin
	-- Skip protection if it has been disabled for a particular column.
	-- This usually happens when an api function is running.
	if current_column = disabled_column then
		continue;
	end if;

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


/**
 * Temporarily disable protection for a designated column.
 * Generally useful when running api functions that should update columns
 * when the columns shouldn't otherwise be modified directly by users.
 *
 * *Note:* this only supports one table/column for now.
 *
 * Parameters:
 * - `column_name` - The column for which to skip protection.
 *
 * Returns:
 * - `void`
 *
 * Example:
 * ```sql
 *   perform disable_protection_on_column('column_name');
 *   update table set column_name = 'new value' where id = 1;
 * ```
 */
create or replace function @extschema@.disable_protection_on_column(
	column_name text
)
	returns void
	as $$
declare
begin
	set local "pg_protect_columns.disable_protection_on_column" to column_name;
end;
$$
language plpgsql
strict stable;


/**
 * Removes disabled column protections set via `disable_protection_on_column`. In general, you should *always* call this
 * after performing an update that disabled column protection.
 *
 * *Note:* since `disable_protection_on_column` only supports one table/column for now, this function will clear all disabled columns.
 *
 * Returns:
 * - `void`
 *
 * Example:
 * ```sql
 *   update table set column_name = 'new value' where id = 1;
 *   perform re_enable_column_protection();
 * ```
 */
create or replace function @extschema@.re_enable_column_protection()
	returns void
	as $$
declare
begin
	set local "pg_protect_columns.disable_protection_on_column" to null;
end;
$$
language plpgsql
strict stable;
