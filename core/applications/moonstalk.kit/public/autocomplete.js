// simply renders a list of options after an input with the results of a server-side response; supports keyboard navigation and per-item links/actions

function AutoComplete(request) {
	/* request is a jquery ajax object template with additional attributes
		chars: 2,
		input: '#autocomplete'
		url: '/api/quicksearch',
		render: 'key',
		selected: function(){},
	chars is the offset in the input from which we start querying the server (should match node.quicksearch if targeting quicksearch)
	input is a jquery selector for an html element accepting user input; this element is wrapped in an anonymous span and appended with a ul for the autocomplete results
	url must return a json array with a dictionary for each result, typically containing at least a name and id, and supporting href
	list is a selector for an existing list container which will be populated with list elements for each result; if no element is provided, one will be created with default blur/focus behaviours; note that if you want the autocomplete options to display relative to the input, the input should be enclosed by a container (e.g. span) with a defined position (e.g. relative)
	beforeSend is a function that can be used to show a progress indicator, likewise request.complete to hide the indicator; if not provided, a default indicator is shown in the input
	render is the preferred key from a result to display; default is title but always falls back to name and value
	selected is an optional function to be run when an autocomplete item is selected, and accepts the jquery event, including the result object as returned by the server as event.data
	*/
	request.render = request.render || 'title'; // TODO: support this as a dictionary of functions that render each item based on their class
	request.input = $(request.input);
	request.chars = request.chars || 2;
	request.input.on("keydown", function(event){ KeyControl(event) }); // prevent return key from submitting form and arrow keys from moving insertion point; event can only be cancelled on keydown
	request.input.on("keyup", function(event){ Input(event,request) }); // handle user input // TODO: use keydown for input (captures sooner); cannot capture character on keydown however (only code) as not yet appended to input
	if (!request.list) {
		request.list = $("<ul class='autocomplete'></ul>");
		request.list.insertAfter(request.input);
		request.input.on("blur",function(){ setTimeout(function(){var children=request.list.children().length; request.list.slideUp(20*children)}, 150) }); // hide the results when focus is lost; timeout is required to avoid hiding the target of a pending click before it is captured // TODO: better solution
		request.input.on("focus",function(){var children=request.list.children().length;if(children>0){request.list.slideDown(15*children)}}); // restore any previously hidden results corresponding to the input
		// TODO: fire the query on focus if there is a value but no list; the input may have been restored when going back to a prior page
	} else {
		request.list = $(request.list);
	}
	request.list.on("mouseenter", function(){request.list.children(".hover").removeClass("hover")}); // this resets the hover in case set by keyboard and then pointer
}

function Query(input,request) {
	request.data = request.data || {};
	request.data.match = input.val();
	request.type = request.type || "POST";
	request.timeout = 1000; // TODO: handle timed-out and overlapping queries more elegantly
	request.dataType = "json";
	request.success = function(results){
		return Populate(results,request);
	}
	request.beforeSend = request.beforeSend || function(){
		input.css("background-image", "url(/moonstalk.kit/icons/indeterminate.gif)").css("background-repeat","no-repeat").css("background-position","right center");
	}
	request.complete = request.complete || function(){
		input.css("background-image","none");
	}
	$.ajax(request);
}

function KeyControl(event) {
	var keyCode = event.keyCode ? event.keyCode : event.which;
	if ((keyCode==13)||(keyCode==38)||(keyCode==40)){
		event.preventDefault();
		event.stopPropagation();
	}
}

function Input(event,request) {
	var input = request.input;
	var list = request.list;
	if (input.val().length >=request.chars) {
		var keyCode = event.keyCode ? event.keyCode : event.which;
		if (keyCode == 40){
			// down arrow key
			var current = list.children(".hover").first();
			if (current.length>0) {
				current.removeClass("hover");
				if (current ==list.children().last()){
					list.children().first().addClass("hover");
				} else {
					current.next().addClass("hover");
				}
			} else {
				list.children().first().addClass("hover");
			}
		} else if (keyCode == 38){
			// up arrow key
			var current = list.children(".hover").first();
			if (current.length>0) {
				current.removeClass("hover");
				if (current ==list.children().first()){
					list.children().last().addClass("hover");
				} else {
					current.prev().addClass("hover");
				}
			} else {
				list.children().last().addClass("hover");
			}
		} else if (keyCode == 13){
			// return key
			list.children(".hover").trigger("click");
		} else {
			// new input
			Query(input,request);
		}
	} else {
		// input deleted
		list.slideUp(15*list.children().length);
		list.children().each(function(i,li){
			$(li).slideUp(15).delay(5).remove();
		})
	}
}

function Populate(results,request) {
	// we don't entirely remove the list, instead we only remove items not in the updated results, and we add items not previously in the list, which provides subtle on-screen item persistence
	request.results = results;
	var list = request.list;
	if (results && results.length >0){
		list.slideDown(15);
		var resultIds = {};
		var existingIds = {};
		for (var i=0; i<results.length; i++) {
			resultIds[results[i].id] = true;
		}
		// TODO: handle value filtering beyond the handled char depth
		list.children().each(function(i,li){
			if (!resultIds[li.id]){
				$(li).slideUp(25).delay(5).remove();
			} else {
				existingIds[li.id] = true;
			}
		})
		var li;
		for (var i=0; i<results.length; i++) {
			if (!existingIds[results[i].id]){
				li = $('<li id="'+results[i].id+'" class="'+results[i].class+'">'+( results[i][request.render] || results[i].name || results[i].value )+"</li>");
				li.click(request,Selected);
				li.hide();
				list.append(li);
				li.slideDown(25).delay(5);
			}
		}
	} else {
		list.slideUp(15*list.children().length);
	}
}

function Selected(event) {
	// handles the invocation of any per-result attributes, or global handler
	var selected;
	var results = event.data.results;
	for (var i=0; i<results.length; i++) {
		// find the corresponding result item using its id
		if (results[i].id ==event.currentTarget.id){selected=results[i];break;}
	}
	if (event.data.selected) {
		event.data.selected(selected);
	} else if (selected.href) {
		location.href = selected.href;
		return false;
	} else {
		// default behaviour is to set input value to selected
		event.data.input.val(selected.title||selected.name||selected.value);
	}
	event.data.input.next('.autocomplete').children().remove(); // have to cleanup so that if we focus on the input again the prior list is not shown
}
