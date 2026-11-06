## Application warning data models.
type
  ## A Telegram identity to which a warning applies.
  WarningTarget* = object
    userId*: int64
    username*: string

  ## A warning issued by a moderator.
  Warning* = object
    target*: WarningTarget
    reason*: string
