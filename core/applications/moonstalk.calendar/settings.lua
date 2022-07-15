name = "Calendars"
database = {{name="events",}} -- this contains both user and tenant subtables (ids are unique across both) which are arrays of events persisted by database fucntions
_G.calendars = {} -- ephemeral indexes for the events
