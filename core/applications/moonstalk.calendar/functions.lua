--[[ 	Moonstalk Calendar

		Copyright 2010, Jacob Jay.
		Free software, under the Artistic Licence 2.0.
		http://moonstalk.org
--]]

function Days (current,to)
	-- returns an array of months and days for any given timeframe (inclusive)
	if to and to < current then local temp = current; current = to; to = temp end -- swap around
	local os_date = os.date
	local os_time = os.time
	to = os_date("*t",to or current) -- may not have an end in which case it is at a single point in time (e.g. a marker)
	current = os_date("*t",current)
	local days = {}
	while true do
		table.insert(days,{year=current.year, month=current.month, day=current.day, wday=current.wday, yday=current.yday})
		if current.year ==to.year and current.month ==to.month and current.day ==to.day then break end
		current.day = current.day + 1; current = os_date("*t",os_time(current)) -- this forces iteration to next month when the day exceeds the month
	end
	return days
end

function Construct(events,start,finish)
	-- for a given array of events, creates a sorted array of date-tables with their unsorted events, constrained by the start, finish timeframe
	local timeframe = Days(start, finish)
	local os_time = os.time
	local os_date = os.date
	for _,date in ipairs(timeframe) do
		date.events = {}
		date.time = os_time({year=date.year,month=date.month,day=date.day,hour=0})
		local startday,finishday
		for _,event in ipairs(events) do
			startday = os_date("*t", event.start)
			startday = os_time({year=startday.year,month=startday.month,day=startday.day,hour=0})
			finishday = os_date("*t", event.finish or event.start)
			finishday = os_time({year=finishday.year,month=finishday.month,day=finishday.day,hour=0})
			if startday <= date.time and finishday >= date.time then
				table.insert(date.events, event)
			end
		end
	end
	return timeframe
end

function NextWeekday(timedate,wday,cutoff_hour)
	-- accepts a timestamp (e.g. now/os.time()) or date table, a weekday number (e.g. 2=Mon) or table of allowed days (e.g. for next Mon or Tue or Wed use {[2]=true,[3]=true,[4]=true}), and an optional cutoff_hour (e.g. 13=1pm)
	-- returns a date table for the next matching weekday after the cutoff_hour (if the target weekday is the same as the timestamp's, and the timestamps's hour is less than the cutoff then the current timestamp is returned); the default cutoff is midnight e.g. next request next monday on a monday at any time would return the monday in 7 days time not the current monday
	if tonumber(wday) then wday = {[tonumber(wday)]=true} end
	local count = 0
	if tonumber(timedate) then timedate = os.date("*t",timedate) end
	if wday[timedate.wday] and timedate.hour <(cutoff_hour or 0) then return timedate end
	while true do
		count = count +1
		timedate.day = timedate.day +1
		timedate = os.date("*t", os.time(timedate))
		if wday[timedate.wday] then
			return timedate
		elseif count >7 then
			return nil,"invalid days"
		end
	end 
end

function TimeDifference(origin_timestamp, target_timestamp, format)
	-- returns days, hours, minutes, and seconds of difference between two timestamps
	-- returns a table unless format is specified as a macro string containing ?() placeholders for any of days,hours,minutes,seconds e.g. "?(days)d?(hours)h"
	local difference = {}
	local difference_time = target_timestamp - origin_timestamp
	if origin_timestamp > target_timestamp then difference_time = origin_timestamp - target_timestamp end -- we don't want to have a negative value
	local difference_total = difference_time
	if format and string.find(format,"?(days)",1,true) then
		difference.days = math.floor(difference_time/time.day)
		difference_time = difference_time -(difference.days *time.day)
	end
	difference.hours = math.floor(difference_time/time.hour)
	difference_time = difference_time -(difference.hours *time.hour)
	difference.minutes = math.floor(difference_time/time.minute)
	difference_time = difference_time -(difference.minutes *time.minute)
	difference.seconds = math.floor(difference_time/time.second)
	difference_time = difference_time -(difference.seconds *time.second)
	if format then return string.gsub(format,"%?%((.-)%)",difference) end
	return difference
end