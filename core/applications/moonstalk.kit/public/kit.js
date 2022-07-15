var moonstalk_Kit = {}; // FIXME: use namespaces; use page.options
client.mobile = /iPhone/.test(navigator.userAgent) ? 'ios' : (/Android/.test(navigator.userAgent)&&/Mobile/.test(navigator.userAgent)) ? 'android' : false
client.portrait = window.innerHeight > window.innerWidth

moonstalk_Kit.Initialise = function(){
	$.fn.extend({
		RelativeDates: function(){
			return this.each( function(){
				var date = $(this).attr('datetime');
				$(this).attr('title',date+' UTC');
				$(this).html(moonstalk_Kit.RelativeDate(date))} )
		},
		preventDoubleSubmit: function() {
		  $(this).on("submit", function() {
		    if (this.beenSubmitted)
		      return false;
		    else
		      this.beenSubmitted = true;
		  });
		},
		bindWithDelay: function( type, data, fn, timeout, throttle ) {
			//MIT license http://github.com/bgrins/bindWithDelay
			if ( $.isFunction( data ) ) {
				throttle = timeout;
				timeout = fn;
				fn = data;
				data = undefined;
			}
			fn.guid = fn.guid || ($.guid && $.guid++);
			return this.each(function() {
				var wait = null;
				function cb() {
					var e = $.extend(true, { }, arguments[0]);
					var ctx = this;
					var throttler = function() {
						wait = null;
						fn.apply(ctx, [e]);
					};

					if (!throttle) { clearTimeout(wait); wait = null; }
					if (!wait) { wait = setTimeout(throttler, timeout); }
				}
				cb.guid = fn.guid;
				$(this).bind(type, data, cb);
			});
		},
		scrollTo: function(elem,mobile) {
			if (mobile && page.mobile ==false) {return}
			$(elem).scrollTop($(elem).scrollTop() - $(elem).offset().top);
			return this;
		},
	})

	if (page.focusfield){$("input[name='"+page.focusfield+"']").focus()};
	if ($("time[datetime]")[0]) {
		setInterval(function(){ $("time[datetime]").RelativeDates(); }, 15000);
		$("time[datetime]").RelativeDates();
	}
	$('form').on("submit",function(){$('input[type=submit],button[type=submit]', this).addClass('disabled').attr('disabled', 'disabled').addClass('disabled').val(vocab.submitted).fadeIn();});

}

moonstalk_Kit.SwapVocab = function(condition,a,b){if(condition){return a}return b}
moonstalk_Kit.RelativeDate = function(date,options){
	// accepts a standardised date string (UTC) and returns a short human-readable relative date adjusted to local time, but with diminishing accuracy the older the date is; grouping starts with day-segments (or hour-segments), then days
	// set options.hours: false to hide individual hour values and decrease accuracy to morning/evening/afternoon then days
	// if hours is not false, set options.mins: false to hide individual minute values and decrease accuracy to a few minutes and quarter/half hour, then hours
	// set options.days = false to hide days and instead use 'a few days'
	// set options.abbr = true or {thisyear:true, pastyears:true} to abbreviate months
	options = options || page.RelativeDates || {}
	if(options.abbr==true){options.abbr = {all:true}}; options.abbr = options.abbr || {pastyears:true}
	date = date.split(/\D/)
	date = new Date(date[0],date[1]-1,date[2],date[3],date[4])
	var now = new Date // Local
	var seconds = (now -date) /1000
	var oneday = -1
	var prefix = "reldate_"
	var future = false
	if (seconds <0){future = true; prefix="reldatefuture_"; oneday=1; seconds=seconds *-1}
	if (!options.hours===false){
		if (seconds<30){
			return vocab[prefix+'now']
		} else if (options.mins===false && seconds<480){
			return vocab[prefix+'fewmins']
		} else if (seconds<90){
			return vocab[prefix+'minute']
		} else if (seconds<3300){ // 55 minutes
			if(options.mins===false){
				if (seconds < 1350) {return vocab[prefix+'quarter']} // 17.5mins
				else if (seconds < 2700) {return vocab[prefix+'half']} // 45mins
				else { vocab[prefix+'hour'] }
			}
			return (vocab[prefix+'minutes']).replace(/\?\(minutes\)/, Math.round(seconds/60))
		} else if (seconds<5400){ // 1h30
			return vocab[prefix+'hour']
		} else if (seconds<12600){ // 3h30
			return (vocab[prefix+'hours']).replace(/\?\(hours\)/, Math.round(seconds/3600))
		}
	}
	if (seconds <432000) { // <=5 days
		if (date.getDate()==now.getDate()) { // today
			var hour = date.getHours();
			if (hour <12){
				return vocab['reldate_thismorning']
			} else if (hour <18){
				return vocab['reldate_thisafternoon'];
			} else {
				return vocab['reldate_thisevening'];
			}
		} else if (now.getDate()-1 == date.getDate()){// yesterday
			var hour = date.getHours();
			if (hour <12){
				return vocab[prefix+'onedaymorning']
			} else if (hour <18){
				return vocab[prefix+'onedayafternoon'];
			} else {
				return vocab[prefix+'onedayevening'];
			}
		} else if (options.days ===false){
			return vocabvocab[prefix+'fewdays']
		} else {// 2–5 days
		return (vocab[prefix+'day']).replace(/\?\(day\)/, vocab.reldate_days[date.getDay()])
		}
	} else if (seconds <864000) { // <10 days
		return vocab[prefix+'week']
	} else if (seconds <3024000 && date.getMonth()==now.getMonth()){ // weeks only for current month
		return (vocab[prefix+'weeks']).replace(/\?\(weeks\)/, Math.round(seconds/604800))
	} else if (seconds==0){
		return vocab.beginning
	} else {
		var month = date.getMonth();var thisyear = now.getFullYear();var dateyear = date.getFullYear()
		var month_text = vocab[moonstalk_Kit.SwapVocab(options.abbr.all || options.abbr.pastyears, 'reldate_monthsabbr','reldate_months')][month]
		if (thisyear-1==dateyear){
			return vocab.reldate_inlastyear.replace(/\?\(month\)/, month_text)
		}else if (thisyear!=dateyear){
			return month_text+" '"+date.getFullYear().toString().substr(2)
		}
		if(!options.abbr.all || !options.abbr.thisyear){ month_text = vocab.reldate_months[month] }
		return vocab.reldate_inmonth.replace(/\?\(month\)/, month_text)
	}
}

moonstalk_Kit.DropSequentialText = function(selector,hideParent){
	var prior;var match;var item;
	$(selector).each(function(){
		item = $(this);match = item.text()
		if(match==prior){if(!hideParent){item.css('display','none')}else{item.parent().css('display','none')}}
		prior = match
	})
}
