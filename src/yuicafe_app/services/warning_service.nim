## SQLite-backed moderation persistence.
import db_connector/db_sqlite

import yuicafe_app/config
import yuicafe_app/models/warning

type
  ## Persistent warning storage owned by the bundled application.
  WarningService* = ref object
    database: DbConn

proc newWarningService*(config: DatabaseConfig): WarningService =
  ## Opens the configured database and initializes the warning schema.
  new(result)
  result.database = open(config.path, "", "", "")
  result.database.exec(sql"""
    CREATE TABLE IF NOT EXISTS warnings (
      id INTEGER PRIMARY KEY,
      update_id INTEGER UNIQUE,
      target_user_id INTEGER NOT NULL DEFAULT 0,
      target_username TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL
    )
  """)
  result.database.exec(sql"""
    CREATE INDEX IF NOT EXISTS warnings_target_user_id_idx
    ON warnings(target_user_id)
  """)
  result.database.exec(sql"""
    CREATE TABLE IF NOT EXISTS processed_ban_updates (
      update_id INTEGER PRIMARY KEY
    )
  """)

proc close*(service: WarningService) =
  ## Closes the SQLite connection owned by `service`.
  if not service.isNil and not service.database.isNil:
    service.database.close()
    service.database = nil

proc record*(service: WarningService; updateId: int64; warning: Warning): bool =
  ## Saves `warning` unless Telegram already delivered `updateId`.
  if warning.target.userId <= 0:
    raise newException(ValueError,
      "warning target must have a Telegram user ID")

  if updateId > 0:
    return service.database.execAffectedRows(
        sql"""
      INSERT OR IGNORE INTO warnings (
        update_id, target_user_id, target_username, reason
      ) VALUES (?, ?, ?, ?)
    """, updateId, warning.target.userId, warning.target.username,

warning.reason) > 0

  service.database.exec(sql"""
    INSERT INTO warnings (target_user_id, target_username, reason)
    VALUES (?, ?, ?)
  """, warning.target.userId, warning.target.username, warning.reason)
  true

proc warningsFor*(service: WarningService;
    target: WarningTarget): seq[string] =
  ## Returns warnings addressed to `target`, in creation order.
  if target.userId <= 0:
    return

  for row in service.database.fastRows(
      sql"""
    SELECT reason
    FROM warnings
    WHERE target_user_id = ?
    ORDER BY id
  """, target.userId):
    result.add(row[0])

proc banRecorded*(service: WarningService; updateId: int64): bool =
  ## Returns whether a successful ban for `updateId` was already persisted.
  if updateId <= 0:
    return false

  for _ in service.database.fastRows(
      sql"""
    SELECT 1
    FROM processed_ban_updates
    WHERE update_id = ?
  """, updateId):
    return true

proc recordBan*(service: WarningService; updateId: int64): bool =
  ## Persists a successful ban update exactly once.
  ##
  ## A positive Telegram update ID is required so at-least-once polling does
  ## not repeat a completed ban after its confirmation message fails.
  if updateId <= 0:
    raise newException(ValueError, "ban update ID must be positive")

  service.database.execAffectedRows(sql"""
    INSERT OR IGNORE INTO processed_ban_updates (update_id)
    VALUES (?)
  """, updateId) > 0
