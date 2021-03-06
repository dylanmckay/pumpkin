class CreateBugSummary < ActiveRecord::Migration[5.0]
  def up
    execute <<-end_sql
CREATE VIEW bug_summaries AS (
  WITH
  latest_occurrences AS (
    SELECT DISTINCT ON (bug_id) *
      FROM occurrences
     ORDER BY bug_id, occurred_at DESC
  ),
  latest_events AS (
    SELECT DISTINCT ON (bug_id) *
      FROM events
     ORDER BY bug_id, created_at DESC
  )
  SELECT bugs.id,
         primary_occurrence.message,
         latest_events.name AS latest_event_name,
         latest_events.created_at AS latest_event_at,
         primary_occurrence.occurred_at AS first_occurred_at,
         latest_occurrences.occurred_at AS last_occurred_at,
         (CASE WHEN latest_events.name = 'closed' THEN latest_events.created_at ELSE NULL END) AS closed_at,
         (SELECT COUNT(1) FROM occurrences WHERE bug_id = bugs.id) AS occurrence_count
    FROM bugs
    JOIN latest_events
      ON bugs.id = latest_events.bug_id
    JOIN latest_occurrences
      ON bugs.id = latest_occurrences.bug_id
    JOIN occurrences AS primary_occurrence
      ON bugs.primary_occurrence_id = primary_occurrence.id
);
    end_sql
    execute "DROP VIEW bug_with_latest_details"
  end

  def down
    execute <<-end_sql
 CREATE OR REPLACE VIEW bug_with_latest_details AS (
  WITH
  latest_occurrences AS (
    SELECT DISTINCT ON (bug_id) * FROM occurrences ORDER BY bug_id, occurred_at DESC
  ),
  latest_events AS (
    SELECT DISTINCT ON (bug_id) * FROM events ORDER BY bug_id, created_at DESC
  )
  SELECT bugs.id,
     bugs.primary_occurrence_id,
     bugs.created_at,
     bugs.updated_at,
     latest_events.id AS latest_event_id,
     latest_events.name AS latest_event_name,
     latest_occurrences.occurred_at AS last_occurred_at
    FROM bugs
     JOIN latest_events ON bugs.id = latest_events.bug_id
     JOIN latest_occurrences ON bugs.id = latest_occurrences.bug_id
)
;
    end_sql

    execute "DROP VIEW bug_summaries"
  end
end
