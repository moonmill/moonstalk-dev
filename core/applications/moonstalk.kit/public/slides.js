// Progressive loading for Jquery.cycle; Jacob Jay 2012 CC-BY
// Requires jQuery.cycle, optionally spin.js
// Adds a callback handler to a jquery.cycle slideshow which preloads the next slide's photo (first img element of slide containers with the class 'photo') or insert html content, whilst the current slide is still on screen and before the next is shown, pausing until the image has downloaded; this also works for pager clicks if the gotoSlide(n) function is called
// TODO: the UI should block access to not yet loaded slides on use of goto to avoid queuing up too many images, as the slideshow only progresses to the most recently requested slide once ti has loaded
// TODO: load spin here with dominoes if specified, rather than waiting for it earlier

var slides = {};
slides.Show = function(options){
	slides.options = options; // the options map is shared with cycle, thus we should not use any of its option names unless we reset them
	// progressive slides options
	if (typeof slides.options.data =='string'){slides.options.data = window[slides.options.data]}else{slides.options.data = slides.options.data || []}; // per-slide behaviours: html:'markup' loader:'funcname'
	slides.options.in = slides.options.in || '#slideshow' // selector for slides container
	// options.slide -- selector for slide elements (optional)
	slides.options.slideshow = $(slides.options.in);
	if (slides.options.data.length > 0){ slides.options.slideCount = slides.options.data.length }else{slides.options.slideCount = slides.options.slideshow.children().length};
	slides.options.currentSlide = 0
	// cycle options
	slides.options.next = slides.options.next || slides.options.slide // the element on which clicking will advance to the next slide, defaults to the entire slide; set to false to disable
	// options.autostop slide number to end on
	if (slides.options.next==null) { slides.options.next = slides.options.in+" >" }
	if (slides.options.next) { $(slides.options.next).click('next',slides.Jump) }
	slides.options.next = null // we overloaded the next behaviour to pause the slideshow
	slides.options.delay = slides.options.delay || 4200;
	slides.options.timeout = slides.options.timeout || 3200;
	slides.options.fx = slides.options.fx || 'scrollHorz';
	slides.options.speed = slides.options.speed || 600;
	slides.options.fastOnEvent = slides.options.fastOnEvent || 300;
	if (slides.options.data.length > 0){
		slides.options.autostopCount = slides.options.autostopCount || slides.options.data.length+1
		slides.options.autostop = slides.options.autostop || true
	};
	slides.options.after = slides._after;
	slides.options.before = slides._before; // we use the before callback instead of after as we gain its additional duration plus the timeout to complete loading
	slides.options.containerResize = slides.options.containerResize || 0;
	// event handlers and UI niceties
	// use the spin.js resolution-independent spinner
	if (Spinner){
		slides.options.spinner = new Spinner(slides.options.spinner || {lines:12, length:7, width:4, radius:10, color:'#fff', speed:1, trail:60, shadow:true, hwaccel:true} )
	};
	// start the slideshow
	slides.options.slideshow.cycle(slides.options)
};
slides.Jump = function(n){
	// 0-based index -- FIXME: use 1-based
	// before going to a slide directly we have to ensure its content is loaded, as the before (progressiveLoader) handler is not called
	// user interaction stops auto advance
	// accepts 'next' which is a cycle param
	slides.options.stopped = true; slides.options.slideshow.cycle('pause');
	var targetSlide
	if (typeof n =='object'){
		n = n.data; // next|previous
		targetSlide = slides.options.currentSlide +1
	}else{
		targetSlide = n
	};
	if (slides._check(targetSlide)){
		slides.options.slideshow.cycle(n);
	}else{
		slides.options.destinationSlide = targetSlide;
		// populate the next slide in readiness for advancing
	};
};
slides.populate = function(n){
	// optional deferred html insert into each slide
	if (slides.options.data[n] && slides.options.data[n].html){
		var slide = $(slides.options.slideshow.children(slides.options.slide)[n])
		// TODO: add the slide container if missing
		$(slide).html(slides.options.data[n].html)
		slides.options.data[n].html=null
	};
	// optional meta loader
	if (slides.options.data[slides.options.targetSlide] && slides.options.data[slides.options.targetSlide].loader){
		window[slides.options.data[slides.options.targetSlide].loader](); // called every time the slide is displayed
	};
};
slides._before = function(current, next, options, forward){
	// provides opportunity to pause before reaching next slide
	var targetSlide = slides.options.targetSlide || options.currentSlide+1
	if (slides._check(targetSlide) == true){
		slides.populate(targetSlide+1)
		slides.options.targetSlide = null
	}
};
slides._after = function(current, next, options){
	// maintain in-sequence counter (can't use beforeSlide as it is called each time we try to advance to a slide, thus counter is repetitive)
	slides.options.currentSlide = options.currSlide // we need to know the index of the next slide for goto('next')
}
slides._check = function(n){
	// check if the target slide is ready and if not pause until it is ready
	if (typeof(n) =='string'){n=slides.options.currentSlide+1}
	slides.populate(n)
	var image = $($(slides.options.slideshow).children(slides.options.slide)[n]).find('img.deferred')[0]; // from the nth slide find the first img with class deferred
	if (image && image.complete !=true) {
		slides.options.slideshow.cycle('pause');
		if (slides.options.spinner){
			slides.options.spinner.spin();
			if (slides.options.spinner_css){ $(slides.options.spinner.el).css(slides.options.spinner_css)};
		};
		$(image).on("load",n,slides._loaded);
		return false;
	};
	return true;
};
slides._loaded = function(event){
	if (slides.options.stopped != true) {
		// no goto has been requested, therefore just resume auto advance
		if (slides.options.spinner){slides.options.spinner.stop()};
		slides.options.targetSlide = event.data+1
		slides.options.slideshow.cycle('resume');
	} else if (event.data == slides.options.destinationSlide){
		// the loaded slide is the most recently requested; this prevents as fats sequence of slide movements following multiple goto requests from a UI without progress feedback
		if (slides.options.spinner){slides.options.spinner.stop()};
		slides.options.targetSlide = event.data+1
		slides.options.destinationSlide = null;
		slides.options.slideshow.cycle(event.data);
	} else {
		// else the loaded slide is not the last requested, so don't advance
	}
};
