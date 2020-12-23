/-  *ucal, *hora, components=ucal-components, ucal-timezone, ucal-store
/+  *hora, utc=ucal-timezones-utc, tzmaster=ucal-timezones-master
|%
::  TODO for can-{read, write}-cal do we want to allow moons the
::  same permissions as ships? (team:title original-ship potential-moon)
::  maybe just for the owner, but not other ships.
::
::  +can-read-cal: check if a particular ship has read access to a calendar.
::
++  can-read-cal
  |=  [[owner=ship permissions=calendar-permissions] =ship]
  ^-  flag
  ?:  (team:title owner ship)
    &
  ?~  readers.permissions
    &
  ?|  (~(has in u.readers.permissions) ship)
      (~(has in writers.permissions) ship)
      (~(has in acolytes.permissions) ship)
  ==
::  +can-write-cal: check if a particular ship has write access to a calendar.
::
++  can-write-cal
  |=  [[owner=ship permissions=calendar-permissions] =ship]
  ^-  flag
  ?:  (team:title owner ship)
    &
  ?|  (~(has in writers.permissions) ship)
      (~(has in acolytes.permissions) ship)
  ==
::  +can-change-permissions: check if a particular ship can change
::  calendar permissions.
::
++  can-change-permissions
  |=  [[owner=ship permissions=calendar-permissions] =ship]
  ^-  flag
  ?|  (team:title owner ship)
      (~(has in acolytes.permissions) ship)
  ==
::  +set-permissions: change the permissions for a target ship
::  to the specified role. if role is unit, revoke permissions
::  for the target ship instead.
::
++  set-permissions
  |=  [permissions=calendar-permissions =ship role=(unit calendar-role)]
  ^-  calendar-permissions
  =/  new-perms=calendar-permissions  (revoke-permissions permissions ship)
  ?~  role
    new-perms
  ?-    u.role
      %reader
    ::  it doesn't make sense to add a reader to a public calendar so
    ::  we can use need.
    %=  new-perms
      readers  `(~(put in (need readers.new-perms)) ship)
    ==
  ::
      %writer
    %=  new-perms
      writers  (~(put in writers.new-perms) ship)
    ==
  ::
      %acolyte
    %=  new-perms
      acolytes  (~(put in acolytes.new-perms) ship)
    ==
  ==
::  +revoke-permissions: revoke all of ship's permisisons (unless the calendar
::  is public - then they'll still be able to read).
::
++  revoke-permissions
  |=  [permissions=calendar-permissions =ship]
  ^-  calendar-permissions
  :+  ?~  readers.permissions  ~  `(~(del in u.readers.permissions) ship)
    (~(del in writers.permissions) ship)
  (~(del in acolytes.permissions) ship)
::  +events-overlapping-in-range: given an event and a range, produces
::  a unit event (representing whether the input event overlaps with
::  the target range) and a list of projected events (if the event is
::  recurring, these are the generated instances that also fall in range).
::  IMPORTANT: THE INPUT TIMES ARE ASSUMED TO BE IN UTC.
::  TODO could change above by also taking in a timezone and applying adjustment?
++  events-overlapping-in-range
  =<
  |=  [e=event start=@da end=@da]
  ^-  [(unit event) (list projected-event)]
  ?>  (lte start end)
  ::  adjust by timezone
  =/  =tz:ucal-timezone  (get-tz:tzmaster tzid.data.e)
  =/  [start=@da end=@da]  [(from-utc.tz start) (from-utc.tz end)]
  =/  [event-start=@da event-end=@da]  (moment-to-range when.data.e)
  ?~  era.e
    :_  ~
    ?:  (ranges-overlap start end event-start event-end)
      `e
    ~
  ::  TODO this is implementation dependent on overlapping-in-range
  ::  returning the original moment first if it does in fact overlap.
  ::  maybe there's a better way to handle this?
  ::  ah actually, if it overlaps it'll be in front but if it starts
  ::  in the range it'll be at the very end of l. I mean I guess knowing
  ::  that, we can't really do much except check both cases...
  ::  FIXME we could also just do the most general "filter" approach for now
  ::  and revisit if performance here is crushingly bad or something...
  =/  l=(list moment)  (overlapping-in-range start end when.data.e u.era.e)
  =/  f  (bake (curr project [data.e u.era.e]) moment)
  =/  [original=(list moment) proj=(list moment)]
      (skid l |=(m=moment =(m when.data.e)))
  :_  (turn proj f)
  ?~  original
    ~
  ?>  =((lent original) 1)
  `e
  |%
  ++  project
    |=  [m=moment ed=event-data =era]
    ^-  projected-event
    [ed(when m) era]
  --
::  +make-uuid: utility for generating random terms with a fixed length.
::  this breaks the term into groups of 4 for easier reading
::
++  make-uuid
  =>
  |%
  ::  $rng: type for cores generated by seeding og
  ::
  ++  rng  _~(. og 0)
  ::  +get-random-char: gets a term of a single ascii character [a-z]
  ::
  ++  get-random-char
    |*  =rng
    ^-  [term ^rng]
    =/  [incr=@ud continuation=^rng]  (rads:rng 26)
    [`term`(add 'a' incr) continuation]
  ::  +make-term-list: build the list of individual terms. we build the list
  ::  backwards and reverse upon return.
  ::
  ++  make-term-list
    |*  [=rng len=@ud acc=(list term)]
    ^-  (list term)
    ?:  =(len 0)
      (flop acc)
    =/  acc=(list term)
        ?:  =(0 (mod len 4))
          [`term`'-' acc]
        acc
    =/  [nxt=term continuation=^rng]  (get-random-char rng)
    %^  make-term-list  continuation
      (dec len)
    [nxt acc]
  --
  |=  [eny=@uv len=@ud]
  ^-  term
  ?>  (gth len 0)
  =/  [first=term =rng]  (get-random-char ~(. og eny))
  `term`(crip (make-term-list rng (dec len) ~[first]))
::  +from-digits:  converts a list of digits to a single atom
::
++  from-digits
  |=  l=(list @)
  ^-  @ud
  (roll l |=([cur=@ud acc=@ud] (add (mul 10 acc) cur)))
::  +vcal-to-ucal: converts a vcalendar to our data representation
::
++  vcal-to-ucal
  |=  [=vcalendar:components =calendar-code owner=@p now=@da]
  ^-  [calendar (list event)]
  =/  cal=calendar
    :*
      owner
      calendar-code
      (crip prodid.vcalendar)
      [`~ `~]  :: default permissions are private
      now
      now
    ==
  :-  cal
  %-  head
  %+  reel
    events.vcalendar
  |=  [cur=vevent:components events=(list event) code=event-code]
  ^-  [(list event) event-code]
  =/  res=(unit event)  (vevent-to-event cur code calendar-code owner now)
  ?~  res
    [events code]
  [[u.res events] +(code)]
::  +vevent-to-event: attempts to parse event from vevent
::
++  vevent-to-event
  |=  [v=vevent:components =event-code =calendar-code owner=@p now=@da]
  ^-  (unit event)
  =/  m=moment  (parse-moment ical-time.dtstart.v end.v)
  =/  start=@da  (head (moment-to-range m))
  =/  res=(unit (unit era))  (parse-era start rrule.v rdate.v exdate.v)
  ?~  res
    ~
  %-  some
  ^-  event
  :*
    ^-  event-data
    :*
      event-code
      calendar-code
      %:  about
        owner
        (fall created.v now)
        (fall last-modified.v now)
      ==
      %:  detail
        (fall (bind summary.v crip) '')
        (bind description.v crip)
        (parse-location location.v geo.v)
      ==
      m
      `invites`~  :: TODO parse invites? what does this look like?
      `rsvp`%yes  :: TODO parse rsvp? unclear what this should be
      (fall tzid.dtstart.v "utc")
    ==
    u.res
  ==
::
++  parse-location
  |=  [loc=(unit tape) geo=(unit latlon:components)]
  ^-  (unit location)
  ::  TODO how do we want to handle situations where only geo is specified?
  ::  our current definition of location doesn't handle it - update?
  ?~  loc
    ~
  =/  address=@t  (crip u.loc)
  ?~  geo
    `[address ~]
  `[address `[(ryld lat.u.geo) (ryld lon.u.geo)]]
::
++  parse-moment
  |=  [start=ical-time:components end=event-ending:components]
  ^-  moment
  ?:  ?=([%date *] start)
    ?:  ?=([%dtend *] end)
      ?:  ?=([%date *] end.end)
        [%days d.start +((div (sub d.end.end d.start) ~h24))]
      [%period d.start d.end.end]
    [%block d.start duration.end]
  ?:  ?=([%dtend *] end)
    ?:  ?=([%date *] end.end)
      [%period d.start d.end.end]
    [%period d.start d.end.end]
  [%block d.start duration.end]
::  +parse-era: given parsed components of rrule, produce an era.
::  if the rrule cannot be parsed into our era, produce ~. If there
::  is no rrule, produce [~ ~]. if there is a valid rrule, produce
::  the era.
::
++  parse-era
  =>
  |%
  ++  rrule-day-to-weekday
    ^-  (map rrule-day:components weekday)
    %-  ~(gas by *(map rrule-day:components weekday))
    ^-  (list [rrule-day:components weekday])
    :~
      [%su %sun]
      [%mo %mon]
      [%tu %tue]
      [%we %wed]
      [%th %thu]
      [%fr %fri]
      [%sa %sat]
    ==
  --
  |=  [start=@da rr=(unit rrule:components) rdate=(list rdate:components) exdate=(list ical-time:components)]
  ^-  (unit (unit era))
  ?~  rr
    [~ ~]
  =/  et=(unit era-type)
      ?~  count.u.rr
        ?~  until.u.rr
          `[%infinite ~]
        ?:  ?=([%date *] u.until.u.rr)
          `[%until d.u.until.u.rr]
        `[%until d.u.until.u.rr]
      ?~  until.u.rr
        `[%instances u.count.u.rr]
      ::  can't specify both count and until
      ~
  ?~  et
    ~
  =/  r=(unit rrule)
      ^-  (unit rrule)
      ?+  freq.u.rr
        ~
      ::
          %daily
        `[%daily ~]
      ::
          %weekly
        ::  byweekday.u.rr can be empty, so we also include the current weekday.
        ::  we don't use weeknum in this rule.
        =/  weekdays=(set weekday)
            %-  silt
            %+  turn
              byweekday.u.rr
            |=  cur=rrule-weekdaynum:components
            (~(got by rrule-day-to-weekday) day.cur)
        %-  some
        :-  %weekly
        (~(put in weekdays) (get-weekday start))
      ::
          %monthly
        =/  d=date  (yore start)
        ::  if we have bymonthday specified, it's a %on rule,
        ::  otherwise it's a %weekday rule
        ?~  bymonthday.u.rr
          ::  FIXME check the weekday start falls on is in line
          ::  with what the rule specifies? verify with byday?
          ::  also how to tell fourth and last apart?
          %-  some
          :+  %monthly
            %weekday
          ::  1-7 -> 0, 8-14 -> 1, 15->21 -> 2, 21-28 -> 3, 29-31 -> 4
          =/  res  (div (dec d.t.d) 7)
          ?:  =(res 0)
            %first
          ?:  =(res 1)
            %second
          ?:  =(res 2)
            %third
          ?:  =(res 3)
            ::  TODO for now always produce %fourth
            ::  but this could also be %last
            %fourth
          %last
        =/  [s=flag delta=@ud]  (old:si i.bymonthday.u.rr)
        ::  now we want to check the number of days in our target month
        =/  days=@ud  (days-in-month m.d y.d)
        ?:  (gth days delta)
          ~
        =/  target=@ud
            ?:  s
              delta
            +((sub days delta))
        ::  if rrule day doesn't line up with the start date
        ::  the rule is invalid
        ?:  =(target d.t.d)
          `[%monthly %on ~]
        ~
      ::
          %yearly
        `[%yearly ~]
      ==
  ?~  r
    ~
  ``[u.et interval.u.rr u.r]
::
++  permissions-to-json
  =<
  |=  permissions=calendar-permissions
  %-  pairs:enjs:format
  :~  ['acolytes' (ships-to-json acolytes.permissions)]
      ['writers' (ships-to-json writers.permissions)]
      ['readers' (ships-to-json (fall readers.permissions ~))]
      ['public' [%b =(readers.permissions ~)]]
  ==
  |%
  ++  ships-to-json
    |=  ships=(set @p)
    ^-  json
    :-  %a
    %+  turn
      ~(tap in ships)
    ship:enjs:format
  --
::
++  calendar-to-json
  |=  cal=calendar
  ^-  json
  =,  format
  %-  pairs:enjs
  :~  ['owner' (ship:enjs owner.cal)]
      ['calendar-code' (tape:enjs (trip calendar-code.cal))]
      ['title' (tape:enjs (trip title.cal))]
      ['permissions' (permissions-to-json permissions.cal)]
      ['date-created' (time:enjs date-created.cal)]
      ['last-modified' (time:enjs last-modified.cal)]
  ==
::
++  json-to-calendar
  |=  jon=json
  ^-  calendar
  !!
::
++  event-data-to-json
  |=  data=event-data
  ^-  json
  =,  format
  =/  [start=@da end=@da]  (moment-to-range when.data)
  ::  TODO handle invites once code supports them
  %-  pairs:enjs
  :~  ['event-code' (tape:enjs (trip event-code.data))]
      ['calendar-code' (tape:enjs (trip calendar-code.data))]
      ::  about
      ['organizer' (ship:enjs organizer.about.data)]
      ['date-created' (time:enjs date-created.about.data)]
      ['last-modified' (time:enjs last-modified.about.data)]
      ::  detail
      ['title' (tape:enjs (trip title.detail.data))]
      ['desc' (tape:enjs (trip (fall desc.detail.data '')))]
      ::  TODO parse and send lat/lon as well
      ['location' (tape:enjs (trip ?~(loc.detail.data '' address.u.loc.detail.data)))]
      ['start' (time:enjs start)]
      ['end' (time:enjs end)]
      ['tzid' (tape:enjs tzid.data)]
  ==
::
++  event-to-json
  |=  ev=event
  ^-  json
  =,  format
  %-  pairs:enjs
  :~  ['data' (event-data-to-json data.ev)]
      ['era' ?~(era.ev ~ (era-to-json u.era.ev))]
  ==
::
++  projected-event-to-json
  |=  proj=projected-event
  ^-  json
  =,  format
  %-  pairs:enjs
  :~  ['data' (event-data-to-json data.proj)]
      ['era' (era-to-json source.proj)]
  ==
::
::
++  era-to-json
  =,  format
  =<
  |=  =era
  ^-  json
  %-  pairs:enjs
  :~  ['interval' (numb:enjs interval.era)]
      ['type' (era-type-to-json type.era)]
      ['rrule' (rrule-to-json rrule.era)]
  ==
  |%
  ++  era-type-to-json
    |=  et=era-type
    ^-  json
    %-  frond:enjs
    ?:  ?=([%until *] et)
      ['until' (time:enjs end.et)]
    ?:  ?=([%instances *] et)
      ['instances' (numb:enjs num.et)]
    ?:  ?=([%infinite *] et)
      ['infinite' ~]
    !!
  ::
  ++  rrule-to-json
    |=  rr=rrule
    ^-  json
    %-  frond:enjs
    ?:  ?=([%daily *] rr)
      ['daily' ~]
    ?:  ?=([%weekly *] rr)
      :-  'weekly'
      ^-  json
      :-  %a
      %+  turn
        ~(tap in days.rr)
      |=  w=weekday
      ^-  json
      (tape:enjs (trip w))
    ?:  ?=([%monthly *] rr)
      :-  'monthly'
      ?:  ?=([%on *] form.rr)
        (tape:enjs "on")
      ?:  ?=([%weekday *] form.rr)
        (tape:enjs (trip instance.form.rr))
      !!
    ?:  ?=([%yearly *] rr)
      ['yearly' ~]
    !!
  --
::
++  ucal-action-to-json
  |=  act=action:ucal-store
  ^-  json
  !!
::
++  ucal-action-from-json
  =<
  |=  jon=json
  ^-  action:ucal-store
  =,  format
  ::  Format should be key -> json of fields
  %-  tail
  %.  jon
  %-  of:dejs
  :~  [%create-calendar convert-create-calendar]
      [%update-calendar convert-update-calendar]
      [%delete-calendar convert-delete-calendar]
      [%create-event convert-create-event]
      [%update-event convert-update-event]
      [%delete-event convert-delete-event]
      [%change-rsvp convert-change-rsvp]
      [%import-from-ics convert-import]
      [%change-permissions convert-change-permissions]
  ==
  |%
  ++  convert-create-calendar
    |=  jon=json
    ^-  action:ucal-store
    :-  %create-calendar
    !!
  ++  convert-update-calendar
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-delete-calendar
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-create-event
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-update-event
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-delete-event
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-change-rsvp
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-import
    |=  jon=json
    ^-  action:ucal-store
    !!
  ++  convert-change-permissions
    |=  jon=json
    ^-  action:ucal-store
    !!
  --
--
