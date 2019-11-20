ALTER SYSTEM SET wal_level='logical';
ALTER SYSTEM SET max_wal_senders='10';
ALTER SYSTEM SET max_replication_slots='10';

-- Table for testing
CREATE TABLE public.users (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  first_name text,
  last_name text,
  info jsonb,
  inserted_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

INSERT INTO 
    public.users (first_name, last_name) 
VALUES 
    ('Joe', 'Blogs'),
    ('Jane', 'Doe');

-- Function for broadcasts
CREATE FUNCTION public.broadcast_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    current_row RECORD;
	new_row_json jsonb;
	old_row_json jsonb;
	new_row_json_cleansed jsonb;
	old_row_json_cleansed jsonb;
  BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
      current_row := NEW;
    ELSE
      current_row := OLD;
    END IF;
    IF (TG_OP = 'INSERT') THEN
      OLD := NEW;
    END IF;
   
   select into new_row_json to_json(NEW);
   select into old_row_json to_json(OLD);
  
   -- It turns out that NOTIFY only supports up to 8000 bytes (~4000 chars?)
   -- If it exceeds this limit it will throw an error.
   -- To prevent this error & regression, we will never notify the changes to any column named "data".
   -- Also we have to remove "schedule" because that is used in the assignments table, and it's how we found the bug/limitation
   select into new_row_json_cleansed (new_row_json - 'data' - 'schedule')::jsonb;
   select into old_row_json_cleansed (old_row_json - 'data' - 'schedule')::jsonb;
  
   PERFORM pg_notify(
      'db_changes',
      json_build_object(
        'table', TG_TABLE_NAME,
        'type', TG_OP,
        'id', current_row.id,
        'new_row_data', new_row_json_cleansed,
        'old_row_data', old_row_json_cleansed
      )::text
    );
  RETURN current_row;
  END;
  $$;


-- Create the Replication publication 
CREATE PUBLICATION supabase_realtime FOR ALL TABLES;

-- Create a NOTIFY example
CREATE TRIGGER users_changed_trigger AFTER INSERT OR UPDATE ON public.users FOR EACH ROW EXECUTE PROCEDURE public.broadcast_changes();