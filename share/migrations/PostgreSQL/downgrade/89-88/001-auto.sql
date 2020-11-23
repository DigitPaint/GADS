-- Convert schema '/home/abeverley/git/GADS/share/migrations/_source/deploy/89/001-auto.yml' to '/home/abeverley/git/GADS/share/migrations/_source/deploy/88/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE instance DROP CONSTRAINT instance_fk_view_limit_id;

;
DROP INDEX instance_idx_view_limit_id;

;
ALTER TABLE instance DROP COLUMN view_limit_id;

;

COMMIT;

